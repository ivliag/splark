import SplarkKit
import SwiftUI

/// One row of the panel (spec §4.3, the prototype's activity-log style): the spark at the item's level, a quiet
/// "time · source" line, then a bold lead and the rest. Hover swaps the meta line for a toolbar and shows ✓; a click opens
/// the messages, a reply field and reactions.
struct InboxRowView: View {
    let item: InboxItem
    let model: PanelModel
    let now: Date
    var forceHover = false   // for snapshots

    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private var expanded: Bool { model.expanded == item.id }
    private var showToolbar: Bool { (hovering || forceHover) && !expanded }

    var body: some View {
        let palette = Palette(scheme)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                SparkView(level: item.level.spark)
                    .foregroundStyle(palette.spark)
                    .frame(width: 11, height: 16)
                    .help(item.reason)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Presenter.metaLine(item, now: now))
                        .font(Theme.font(11.5))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                        .opacity(showToolbar ? 0 : 1)
                        .overlay(alignment: .topLeading) { if showToolbar { toolbar.offset(x: -5, y: -4) } }
                    summary(palette)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ReadButton(help: "Mark as read in Slack", double: false) { model.markRead(item) }
                    .opacity(hovering || forceHover || expanded ? 1 : 0)
                    .padding(.top, 2)
            }
            if expanded { detail(palette).padding(.leading, 22).padding(.top, 9) }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 11, trailing: 6))
        .background(RoundedRectangle(cornerRadius: 10).fill(hovering || forceHover || expanded ? palette.rowHover : Ink(0, opacity: 0)))
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(item) }
        .onHover { hovering = $0 }
    }

    private func summary(_ palette: Palette) -> some View {
        let quiet = item.level == .fyi
        let color = quiet ? palette.secondary : palette.text
        return (Text(item.lead).font(Theme.font(13, quiet ? NSFont.Weight(rawValue: 0.26) : Theme.leadWeight)).foregroundColor(color.color)
                + Text(item.rest.isEmpty ? "" : " " + item.rest).font(Theme.font(13)).foregroundColor(color.color))
            .lineSpacing(2.5)
            .lineLimit(expanded ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var toolbar: some View {
        HStack(spacing: 1) {
            ChipButton(help: "Reply", action: { model.startReply(item) }) { Image(systemName: "arrowshape.turn.up.left").font(.system(size: 11.5)) }
            reactions
            ChipButton(help: "Open in Slack", action: { Task { await model.open(item) } }) { Image(systemName: "arrow.up.forward.square").font(.system(size: 11.5)) }
        }
    }

    private var reactions: some View {
        ForEach(Reaction.allCases, id: \.self) { reaction in
            ChipButton(help: "React \(reaction.emoji)", action: { Task { await model.react(item, reaction) } }) {
                Text(reaction.emoji).font(.system(size: 13))
            }
        }
    }

    private func detail(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                if item.earlier > 0 || item.moreEarlier {
                    Text("and \(item.earlier)\(item.moreEarlier ? "+" : "") earlier").font(Theme.font(11)).foregroundStyle(palette.tertiary)
                }
                ForEach(Array(item.messages.enumerated()), id: \.offset) { _, message in
                    VStack(alignment: .leading, spacing: 1) {
                        (Text(message.author).font(Theme.font(11, .semibold)).foregroundColor(palette.secondary.color)
                         + Text(" · " + Presenter.clockTime(SlackTS.date(message.ts))).font(Theme.font(11)).foregroundColor(palette.tertiary.color))
                        Text(message.text).font(Theme.font(12)).foregroundStyle(palette.secondary).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 9)
            ReplyField(item: item, model: model)
            HStack(spacing: 1) {
                reactions
                ChipButton(help: "Open in Slack", action: { Task { await model.open(item) } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.square").font(.system(size: 11.5))
                        Text("Open in Slack")
                    }
                }
                Spacer(minLength: 8)
                Text("↵ send · esc close").font(Theme.font(10.5)).foregroundStyle(palette.tertiary)
            }
            .padding(.leading, -5)
            .padding(.top, 6)
        }
    }
}

/// "Reply in thread" / "Message Marta Ruiz". Enter sends, Esc collapses; the text stays if sending fails.
struct ReplyField: View {
    let item: InboxItem
    let model: PanelModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot
    @FocusState private var focused: Bool

    var body: some View {
        let palette = Palette(scheme)
        let draft = Binding(get: { model.drafts[item.id] ?? "" }, set: { model.drafts[item.id] = $0 })
        let ready = !draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.sending.contains(item.id)
        HStack(spacing: 6) {
            Group {
                if isSnapshot {
                    Text(draft.wrappedValue.isEmpty ? item.replyPlaceholder : draft.wrappedValue)
                        .foregroundStyle(draft.wrappedValue.isEmpty ? palette.tertiary : palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("", text: draft, prompt: Text(item.replyPlaceholder).foregroundColor(palette.tertiary.color))
                        .textFieldStyle(.plain)
                        .foregroundStyle(palette.text)
                        .focused($focused)
                        .onSubmit { Task { await model.send(item) } }
                        .onKeyPress(.escape) {
                            model.escape()
                            return .handled
                        }
                }
            }
            .font(Theme.font(12.5))
            .padding(.vertical, 6)
            Button { Task { await model.send(item) } } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.knock)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(palette.secondary))
                    .opacity(ready ? 1 : 0.22)
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .help("Send")
        }
        .padding(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 3))
        .background(RoundedRectangle(cornerRadius: 9).fill(palette.inputBackground))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.panelBorder, lineWidth: 0.5))
        .onAppear { if model.focusedReply == item.id { focused = true } }
        .onChange(of: model.focusedReply) { _, id in focused = id == item.id }
    }
}
