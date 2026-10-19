import SplarkKit
import SwiftUI

/// The setup window's content (spec §4.4; copy and states as in design/prototype/setup.html).
public struct SetupView: View {
    let model: SetupModel
    @Environment(\.colorScheme) private var scheme

    public init(model: SetupModel) { self.model = model }

    public var body: some View {
        let palette = Palette(scheme)
        VStack(spacing: 0) {
            steps(palette).frame(height: 28)
            Group {
                switch model.step {
                case .welcome: welcome(palette)
                case .slack: slack(palette)
                case .chatgpt: chatgpt(palette)
                case .done: done(palette)
                }
            }
            .padding(EdgeInsets(top: 18, leading: 44, bottom: 30, trailing: 44))
        }
        .frame(width: 560)
        .frame(minHeight: 520, alignment: .top)
        .background(palette.window)
    }

    /// Four sparks in the title bar: bright for the current step, brighter for done ones, dimmed for the rest.
    private func steps(_ palette: Palette) -> some View {
        HStack(spacing: 14) {
            ForEach(model.addingWorkspace ? [] : SetupModel.Step.allCases, id: \.self) { step in
                SparkView(level: step == model.step ? .bright : step.rawValue < model.step.rawValue ? .brighter : .dimmed)
                    .help(["Welcome", "Slack", "ChatGPT", "Done"][step.rawValue])
            }
        }
        .foregroundStyle(palette.spark)
        .padding(.top, 8)
    }

    private func title(_ text: String, _ palette: Palette) -> some View {
        Text(text).font(Theme.font(22, .semibold)).foregroundStyle(palette.text).padding(.top, 6).padding(.bottom, 8)
    }

    // MARK: Welcome

    private func welcome(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            AppIconView(size: 84).padding(.top, 18).padding(.bottom, 8)
            title("Splark", palette)
            RichText(markdown: "Slack, sorted by what needs you.\nClick the spark in your menu bar to see what's unread, summarised and ranked.", size: 13.5)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 11) {
                point(.bright, "**Needs action** first, then **questions for you**, then everything else folded away.", palette)
                point(.brighter, "**Reply, react or mark as read** right from the menu bar. Nothing is sent until you press send.", palette)
                point(.dimmed, "**Private by design.** Your Slack messages go only to your own ChatGPT account for summaries. There's no Splark server.", palette)
            }
            .frame(maxWidth: 400, alignment: .leading)
            Spacer(minLength: 22)
            HStack {
                Text("Takes about two minutes.").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                Spacer()
                WindowButton(title: "Get started") { model.next() }
            }
        }
    }

    private func point(_ level: SparkLevel, _ markdown: String, _ palette: Palette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SparkView(level: level).foregroundStyle(palette.spark).frame(height: 19)
            RichText(markdown: markdown)
        }
    }

    // MARK: Slack

    private func slack(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title(model.addingWorkspace ? "Add a workspace" : "Connect Slack", palette)
            RichText(markdown: model.connected.isEmpty
                     ? "Splark reads your Slack through a **private app that only you install**, so there are no shared servers and no rate limits from a public app."
                     : "Add another workspace the same way, or continue.", size: 13.5)
                .padding(.bottom, 18)
            if !model.connected.isEmpty { workspaces(palette).padding(.bottom, 12) }
            slackBody(palette)
            Spacer(minLength: 18)
            HStack(spacing: 10) {
                if model.slack != .manual && model.slack != .idle {
                    Button("Having trouble?") { model.showManual() }.buttonStyle(.plain).font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                }
                Spacer()
                if model.slack == .connected {
                    WindowButton(title: "+ Add another workspace", kind: .ghost) { model.addAnother() }
                }
                if !model.addingWorkspace { WindowButton(title: "Back", kind: .secondary) { model.back() } }
                WindowButton(title: model.addingWorkspace ? "Done" : "Continue", enabled: model.canContinue) { model.next() }
            }
        }
    }

    private func workspaces(_ palette: Palette) -> some View {
        Card {
            ForEach(Array(model.connected.enumerated()), id: \.offset) { index, workspace in
                if index > 0 { CardSeparator() }
                HStack(spacing: 12) {
                    InitialTile(text: InitialTile.initials(workspace.name))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(workspace.name).font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                        Text("\(workspace.url.flatMap { URL(string: $0)?.host } ?? workspace.teamId) · as \(workspace.userName ?? workspace.userId)")
                            .font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                    }
                    Spacer()
                    HStack(spacing: 6) { SparkView(level: .bright); Text("Connected") }.font(Theme.font(12)).foregroundStyle(palette.secondary)
                }
                .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
            }
        }
    }

    @ViewBuilder private func slackBody(_ palette: Palette) -> some View {
        switch model.slack {
        case .idle, .failed:
            tokenForm(palette)
        case .creating:
            WorkingLine(markdown: "Creating your private Slack app…")
        case .waitingForAllow:
            VStack(alignment: .leading, spacing: 4) {
                WorkingLine(markdown: "Waiting for you to click **Allow** in your browser…")
                HStack(spacing: 14) {
                    Button("My workspace needs an admin to approve apps") { Task { await model.needsApproval() } }
                    Button("Cancel") { model.cancel() }
                }
                .buttonStyle(.plain).font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
            }
        case .allowFailed(let message):
            VStack(alignment: .leading, spacing: 10) {
                MessageBox(level: .bright, markdown: message)
                WindowButton(title: "Try again", kind: .secondary) { Task { await model.retryAllow() } }
            }
        case .waitingForApproval:
            VStack(alignment: .leading, spacing: 16) {
                MessageBox(level: .brighter, markdown: "**Your workspace needs an admin to approve new apps.** Slack has sent them your request. Once it's approved, open Splark's Settings and click **Finish connecting**. You can carry on with setup meanwhile.")
                tokenForm(palette)
            }
        case .connected:
            EmptyView()
        case .manual:
            manualForm(palette)
        }
    }

    private func tokenForm(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                howTo("1", palette) {
                    RichText(markdown: "Open Slack's app settings and, under **Your App Configuration Tokens**, click **Generate Token** for the workspace you want.")
                    MiniButton(title: "Open api.slack.com/apps ↗") { model.openSlackAppSettings() }.padding(.top, 6)
                }
                howTo("2", palette) {
                    RichText(markdown: "Copy the **access token** and paste it here. Splark uses it once to create your own private Slack app, then forgets it.")
                }
            }
            .padding(.bottom, 16)
            HStack(spacing: 8) {
                TokenField(placeholder: "Paste access token (xoxe.xoxp-…)", text: Binding(get: { model.token }, set: { model.token = $0 })) {
                    Task { await model.connect() }
                }
                WindowButton(title: "Connect", enabled: model.canConnect) { Task { await model.connect() } }
            }
            Text("The app lives only in your workspace and only you install it. Your Slack token is stored in your Mac's Keychain.")
                .font(Theme.font(11.5)).foregroundStyle(palette.tertiary).padding(.top, 7)
            if case .failed(let message) = model.slack { MessageBox(level: .bright, markdown: message).padding(.top, 10) }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(["Read messages in conversations you're already in, to find what's unread",
                             "Send replies and reactions as you, only when you click",
                             "Mark conversations as read when you ask it to",
                             "Nothing in channels you're not a member of"], id: \.self) { Text("· " + $0) }
                }
                .font(Theme.font(12)).foregroundStyle(palette.secondary).padding(.top, 4)
            } label: {
                Text("What Splark can do in Slack").font(Theme.font(12)).foregroundStyle(palette.secondary)
            }
            .padding(.top, 12)
        }
    }

    private func howTo<Content: View>(_ number: String, _ palette: Palette, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PixelText(number, scale: 2).foregroundStyle(palette.secondary)
                .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 5).fill(palette.chip))
            VStack(alignment: .leading, spacing: 0) { content() }
        }
    }

    private func manualForm(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RichText(markdown: "If the token route doesn't work, create the app yourself: open the link, click **Create**, then **Install to Workspace**, and paste the **User OAuth Token** here.")
            MiniButton(title: "Create Splark's app on api.slack.com ↗") { model.openManifestLink() }
            HStack(spacing: 8) {
                TokenField(placeholder: "Paste user token (xoxp-…)", text: Binding(get: { model.manualToken }, set: { model.manualToken = $0 })) {
                    Task { await model.connectManual() }
                }
                WindowButton(title: "Connect", enabled: !model.manualToken.isEmpty) { Task { await model.connectManual() } }
            }
            Button("Use a setup token instead") { model.addAnother() }.buttonStyle(.plain).font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
        }
    }

    // MARK: ChatGPT

    private func chatgpt(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Connect ChatGPT", palette)
            RichText(markdown: "Splark uses your **ChatGPT subscription** to summarise and rank unread messages. Messages go to OpenAI only for this, with storage turned off, and never touch any other server.", size: 13.5)
                .padding(.bottom, 18)
            switch model.chatgpt {
            case .idle, .failed:
                WindowButton(title: "Sign in with ChatGPT", wide: true) { Task { await model.signIn() } }
                Text("Opens chatgpt.com in your browser. Works with ChatGPT Plus and Pro.")
                    .font(Theme.font(11.5)).foregroundStyle(palette.tertiary).frame(maxWidth: .infinity).padding(.top, 7)
                if case .failed(let message) = model.chatgpt { MessageBox(level: .bright, markdown: message).padding(.top, 10) }
            case .waiting:
                WorkingLine(markdown: "Finish signing in in your browser…")
            case .signedIn(let account):
                HStack(spacing: 12) {
                    InitialTile(text: String((account.email ?? "?").prefix(1)), size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.email ?? "Signed in").font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                        Text("ChatGPT · signed in").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                    }
                    Spacer()
                    HStack(spacing: 6) { SparkView(level: .bright); Text("Connected") }.font(Theme.font(12)).foregroundStyle(palette.secondary)
                }
                .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.chip))
                .padding(.bottom, 14)
                MessageBox(level: .dimmed, markdown: "Summaries use your **ChatGPT plan's usage**. Splark only summarises conversations that changed and waits for activity to settle, so it uses very little.")
            }
            Spacer(minLength: 18)
            HStack(spacing: 10) {
                Spacer()
                WindowButton(title: "Back", kind: .secondary) { model.back() }
                WindowButton(title: "Continue", enabled: model.canContinue) { model.next() }
            }
        }
    }

    // MARK: Done

    private func done(_ palette: Palette) -> some View {
        VStack(spacing: 0) {
            AppIconView(size: 64).padding(.top, 18).padding(.bottom, 8)
            title("You're set", palette)
            RichText(markdown: model.doneMessage, size: 13.5)
                .multilineTextAlignment(.center)
                .padding(.bottom, 18)
            Card {
                SwitchRow(title: "Open at login", isOn: Binding(get: { model.openAtLogin }, set: { model.openAtLogin = $0 }))
                CardSeparator()
                SwitchRow(title: "Show count next to the spark", detail: "How many items need you",
                          isOn: Binding(get: { model.showCount }, set: { model.showCount = $0 }))
            }
            .frame(maxWidth: 400)
            Spacer(minLength: 18)
            HStack {
                Text("Change this any time in Settings.").font(Theme.font(11.5)).foregroundStyle(palette.tertiary)
                Spacer()
                WindowButton(title: "Done") { model.finish() }
            }
        }
    }
}
