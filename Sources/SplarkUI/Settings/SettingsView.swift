import SplarkKit
import SwiftUI

/// The Settings window's content (spec §4.5): four sections behind tabs in the title bar, in setup's look.
public struct SettingsView: View {
    let model: SettingsModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot
    @State private var channelsHeight: CGFloat = 0

    public init(model: SettingsModel) { self.model = model }

    public var body: some View {
        let palette = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            tabs(palette).frame(maxWidth: .infinity).frame(height: 28)
            VStack(alignment: .leading, spacing: 14) {
                if let message = model.message { MessageBox(level: .bright, markdown: message) }
                switch model.section {
                case .slack: if model.channelPicker != nil { channels(palette) } else { workspaces(palette) }
                case .openAI: chatgpt(palette)
                case .general: general(palette)
                case .about: about(palette)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 28, bottom: 26, trailing: 28))
        }
        .frame(width: 520)
        .background(palette.window)
    }

    private func tabs(_ palette: Palette) -> some View {
        HStack(spacing: 4) {
            ForEach(SettingsModel.Section.allCases, id: \.self) { section in
                let selected = section == model.section
                Button { model.section = section } label: {
                    Text(section.rawValue).font(Theme.font(12, selected ? .semibold : .medium))
                        .foregroundStyle(selected ? palette.text : palette.secondary)
                        .padding(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? palette.chip : Ink(0, opacity: 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    private func heading(_ text: String, _ palette: Palette) -> some View {
        Text(text).font(Theme.font(12, .semibold)).foregroundStyle(palette.secondary)
    }

    private func note(_ text: String, _ palette: Palette) -> some View {
        Text(text).font(Theme.font(11.5)).foregroundStyle(palette.tertiary).fixedSize(horizontal: false, vertical: true)
    }

    /// Asks before something that can't be undone: removing a workspace, resetting Splark.
    private func confirmation(_ title: String, _ detail: String, action: String, _ palette: Palette,
                              cancel: @escaping () -> Void, confirm: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
            RichText(markdown: detail, size: 12.5)
            HStack(spacing: 8) {
                Spacer()
                WindowButton(title: "Cancel", kind: .secondary, action: cancel)
                WindowButton(title: action, action: confirm)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.chip))
    }

    // MARK: Workspaces

    private func workspaces(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Card {
                    ForEach(Array(model.workspaceRows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { CardSeparator() }
                        workspaceRow(row, palette)
                    }
                    if !model.workspaceRows.isEmpty { CardSeparator() }
                    Button { model.addWorkspace() } label: {
                        Text("+ Add workspace").font(Theme.font(13, .medium)).foregroundStyle(palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let removal = model.removal {
                confirmation("Remove \(removal.name)?", model.removalNote, action: "Remove", palette,
                             cancel: { model.cancelRemoval() }, confirm: { Task { await model.confirmRemoval() } })
            }
            HStack(alignment: .top, spacing: 8) {
                SparkView(level: model.badgeLine.hasPrefix("Slack is open") ? .bright : .dimmed).foregroundStyle(palette.spark).padding(.top, 2)
                note(model.badgeLine, palette)
            }
        }
    }

    private func workspaceRow(_ row: WorkspaceRow, _ palette: Palette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            InitialTile(text: row.pending == nil ? InitialTile.initials(row.name) : "?")
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name).font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                        Text("\(row.status.title) · \(row.status.detail)").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        if row.canExcludeChannels { MiniButton(title: "Channels…") { Task { await model.editChannels(row) } } }
                        MiniButton(title: "Remove") { model.askToRemove(row) }
                    }
                }
                if model.working == row.id {
                    HStack(spacing: 8) {
                        CyclingSpark().foregroundStyle(palette.spark)
                        RichText(markdown: "Waiting for you to click **Allow** in your browser…", size: 12)
                        Spacer(minLength: 0)
                        MiniButton(title: "Cancel") { model.cancel() }
                    }
                } else if model.pasting == row.id {
                    HStack(spacing: 8) {
                        TokenField(placeholder: "Paste a new user token (xoxp-…)", text: Binding(get: { model.newToken }, set: { model.newToken = $0 })) {
                            Task { await model.savePastedToken() }
                        }
                        WindowButton(title: "Cancel", kind: .ghost) { model.cancelPasting() }
                        WindowButton(title: "Save", enabled: !model.newToken.isEmpty) { Task { await model.savePastedToken() } }
                    }
                } else if let action = row.action {
                    MiniButton(title: action.title) {
                        Task { await model.perform(action, on: row) }
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
    }

    // MARK: Muted channels

    private func channels(_ palette: Palette) -> some View {
        let picker = model.channelPicker!
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Muted channels in \(picker.name)").font(Theme.font(15, .semibold)).foregroundStyle(palette.text)
                note("Splark leaves muted channels out. Mute one here, or with Mute on its message in the panel. Direct messages can't be muted.", palette)
            }
            TokenField(placeholder: "Search channels", text: Binding(get: { model.channelPicker?.search ?? "" }, set: { model.channelPicker?.search = $0 }),
                       monospaced: false)
            if picker.channels.isEmpty {
                note("Channels appear here after Splark's first catch-up in \(picker.name).", palette).padding(.vertical, 8)
            } else {
                let list = Card {
                    ForEach(Array(picker.shown.enumerated()), id: \.element.id) { index, channel in
                        if index > 0 { CardSeparator() }
                        Button { model.toggleChannel(channel.id) } label: {
                            HStack(spacing: 10) {
                                Checkbox(on: picker.excluded.contains(channel.id))
                                Text(channel.title).font(Theme.font(13)).foregroundStyle(palette.text)
                                if channel.isPrivate { Text("private").font(Theme.font(11)).foregroundStyle(palette.tertiary) }
                                Spacer()
                            }
                            .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if isSnapshot {
                    list
                } else {
                    ScrollView { list.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { channelsHeight = $0 } }
                        .scrollIndicators(.automatic)
                        .frame(height: min(channelsHeight, 300))
                }
            }
            HStack(spacing: 8) {
                note("\(picker.excluded.count) muted", palette)
                Spacer()
                WindowButton(title: "Cancel", kind: .secondary) { model.cancelChannels() }
                WindowButton(title: "Save") { Task { await model.saveChannels() } }
            }
        }
    }

    // MARK: ChatGPT

    private func chatgpt(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Card {
                HStack(spacing: 12) {
                    InitialTile(text: String((model.account?.email ?? "?").prefix(1)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.account.map { $0.email ?? "Signed in" } ?? "Not signed in").font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                        Text(model.account.map { $0.canUsePlan ? "ChatGPT · summaries use your plan's usage" : "ChatGPT · this plan can't be used for summaries" }
                             ?? "Sign in to get summaries. Splark still ranks what's unread without them.")
                            .font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                    }
                    Spacer(minLength: 8)
                    if model.signingIn {
                        CyclingSpark().foregroundStyle(palette.spark)
                        MiniButton(title: "Cancel") { model.cancel() }
                    } else if model.account == nil {
                        MiniButton(title: "Sign in with ChatGPT") { Task { await model.signIn() } }
                    } else {
                        MiniButton(title: "Sign out") { Task { await model.signOut() } }
                    }
                }
                .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                if model.account != nil {
                    CardSeparator()
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Model").font(Theme.font(13)).foregroundStyle(palette.text)
                            Text("Recommended: \(model.recommendedModel ?? "the plan's first model")").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                        }
                        Spacer()
                        ModelMenu(model: model)
                    }
                    .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                }
                CardSeparator()
                SwitchRow(title: "Pause summaries", detail: "Splark keeps ranking what's unread, without summaries",
                          isOn: Binding(get: { model.summariesPaused }, set: { on in Task { await model.setSummariesPaused(on) } }))
            }
            note("Only conversations that changed are summarised. Messages go to OpenAI with storage turned off, and nowhere else.", palette)
        }
    }

    // MARK: General

    private func general(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Card {
                SwitchRow(title: "Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.setOpenAtLogin($0) }))
                CardSeparator()
                SwitchRow(title: "Show count next to the spark", detail: "How many items need you",
                          isOn: Binding(get: { model.showCount }, set: { on in Task { await model.setShowCount(on) } }))
            }
            if model.confirmingReset {
                confirmation("Reset Splark?", "Splark forgets **every workspace, token, setting and summary**, then starts setup again. Your private Slack apps stay until you delete them at api.slack.com/apps.",
                             action: "Reset", palette, cancel: { model.cancelReset() }, confirm: { Task { await model.confirmReset() } })
            } else {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Reset Splark").font(Theme.font(13)).foregroundStyle(palette.text)
                            Text("Forget everything and start setup again").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                        }
                        Spacer()
                        MiniButton(title: "Reset…") { model.askToReset() }
                    }
                    .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
                }
            }
        }
    }

    // MARK: About

    private func about(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            AppIconView(size: 64).padding(.top, 8).padding(.bottom, 10)
            Text("Splark").font(Theme.font(20, .semibold)).foregroundStyle(palette.text)
            Text(model.version).font(Theme.font(12)).foregroundStyle(palette.secondary).padding(.top, 2).padding(.bottom, 12)
            MiniButton(title: "github.com/ivliag/splark ↗") { model.openRepository() }.padding(.bottom, 18)
            RichText(markdown: "Mirroring Slack's Dock badge into the menu bar is an idea from **Doll**. The pixel art is inspired by 1-bit icon sheets.", size: 12)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            MiniButton(title: "Doll on GitHub ↗") { model.openDoll() }.padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The model picker: a menu of the plan's models, the recommended default first. Offscreen snapshots draw its label.
struct ModelMenu: View {
    let model: SettingsModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let palette = Palette(scheme)
        let label = HStack(spacing: 4) {
            Text(model.model ?? "Recommended").font(Theme.font(12, .medium))
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(palette.text)
        .padding(EdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9))
        .background(RoundedRectangle(cornerRadius: 7).fill(palette.chip))
        if isSnapshot {
            label
        } else {
            Menu {
                Button("Recommended (\(model.recommendedModel ?? "first available"))") { Task { await model.chooseModel(nil) } }
                Divider()
                ForEach(model.models, id: \.self) { name in Button(name) { Task { await model.chooseModel(name) } } }
            } label: { label }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }
}

/// A checkbox in the prototype's monochrome: a rounded square, filled with a tick when on.
struct Checkbox: View {
    let on: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(scheme)
        RoundedRectangle(cornerRadius: 4)
            .fill(on ? palette.button : palette.field)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(on ? Ink(0, opacity: 0) : palette.fieldBorder, lineWidth: 1))
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.buttonText) } }
            .frame(width: 16, height: 16)
            .accessibilityLabel(Text(on ? "Muted" : "Not muted"))
    }
}
