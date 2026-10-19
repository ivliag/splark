import SplarkKit
import SwiftUI

/// The panel (spec §4.3): a header, the items that need you, "Just comments" folded at the bottom, an empty state, and a toast.
public struct PanelView: View {
    public enum Layout: Equatable {
        /// In the panel window: scrolls past `maxHeight`, and reports its size so the window can follow it.
        case live(maxHeight: CGFloat)
        /// For previews and offscreen snapshots: everything at its natural height, on a solid background.
        case snapshot
    }

    let inbox: InboxStore
    let status: HeaderStatus?
    let model: PanelModel
    let now: Date
    let layout: Layout
    let onSize: (CGSize) -> Void
    var forceHover: InboxItem.ID? = nil   // snapshots of the hover state

    @Environment(\.colorScheme) private var scheme
    @State private var hoveringPanel = false
    @State private var hoveringComments = false
    @State private var listHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0

    public init(inbox: InboxStore, status: HeaderStatus?, model: PanelModel, now: Date, layout: Layout, onSize: @escaping (CGSize) -> Void = { _ in }) {
        self.inbox = inbox
        self.status = status
        self.model = model
        self.now = now
        self.layout = layout
        self.onSize = onSize
    }

    init(inbox: InboxStore, status: HeaderStatus?, model: PanelModel, now: Date, forceHover: InboxItem.ID?) {
        self.init(inbox: inbox, status: status, model: model, now: now, layout: .snapshot)
        self.forceHover = forceHover
    }

    public var body: some View {
        let palette = Palette(scheme)
        VStack(spacing: 0) {
            header(palette)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            if inbox.items.isEmpty { empty(palette) } else { list(palette) }
        }
        .frame(width: Theme.panelWidth)
        .background(layout == .snapshot ? AnyShapeStyle(palette.panelBackground) : AnyShapeStyle(palette.glassTint))
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelCorner))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelCorner).strokeBorder(palette.panelBorder, lineWidth: 0.5))
        .overlay(alignment: .bottom) { toast(palette) }
        .onHover { hoveringPanel = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
    }

    // MARK: Header

    private func header(_ palette: Palette) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inbox.summary.headline).font(Theme.font(13, .semibold)).foregroundStyle(palette.text)
                if let status {
                    HStack(spacing: 6) {
                        if status.working { CyclingSpark().foregroundStyle(palette.tertiary) }
                        Text(status.text).lineLimit(1)
                    }
                    .font(Theme.font(11.5))
                    .foregroundStyle(palette.tertiary)
                }
            }
            Spacer()
            HStack(spacing: 0) {
                HeaderButton(symbol: "arrow.up.forward.app", help: "Open Slack") { model.openSlackApp() }
                HeaderButton(symbol: "gearshape", help: "Settings") { model.showSettings() }
            }
            .opacity(hoveringPanel ? 1 : 0)
        }
        .padding(EdgeInsets(top: 14, leading: 18, bottom: 10, trailing: 10))
        .frame(minHeight: 48)
    }

    // MARK: List

    @ViewBuilder private func list(_ palette: Palette) -> some View {
        let rows = VStack(spacing: 0) {
            ForEach(inbox.items.filter { $0.level != .fyi }) { item in
                InboxRowView(item: item, model: model, now: now, forceHover: forceHover == item.id)
            }
            comments(palette)
        }
        .padding(EdgeInsets(top: 4, leading: 6, bottom: 10, trailing: 6))

        switch layout {
        case .snapshot:
            rows
        case .live(let maxHeight):
            ScrollView {
                rows.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.never)
            .frame(height: min(listHeight, max(0, maxHeight - headerHeight)))
        }
    }

    @ViewBuilder private func comments(_ palette: Palette) -> some View {
        let comments = inbox.items.filter { $0.level == .fyi }
        if !comments.isEmpty {
            VStack(spacing: 0) {
                Rectangle().fill(palette.separator).frame(height: 0.5).padding(.horizontal, 0)
                HStack(spacing: 11) {
                    Color.clear.frame(width: 11, height: 1)
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(model.commentsOpen ? 90 : 0))
                        (Text("Just comments").font(Theme.font(11.5, .semibold)).foregroundColor(palette.secondary.color)
                         + Text(" · \(comments.count) conversation\(comments.count == 1 ? "" : "s")").font(Theme.font(11.5)))
                    }
                    .foregroundStyle(palette.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ReadButton(help: "Mark all as read in Slack", double: true) { model.markAllRead(comments) }
                        .opacity(hoveringComments ? 1 : 0)
                }
                .padding(EdgeInsets(top: 12, leading: 12, bottom: 8, trailing: 6))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { model.commentsOpen.toggle() } }
                .onHover { hoveringComments = $0 }
                if model.commentsOpen {
                    ForEach(comments) { item in InboxRowView(item: item, model: model, now: now, forceHover: forceHover == item.id) }
                }
            }
            .padding(.top, 10)
        }
    }

    private func empty(_ palette: Palette) -> some View {
        VStack(spacing: 10) {
            SparkView(level: .dimmed).foregroundStyle(palette.spark)
            Text("Nothing unread in Slack.").font(Theme.font(13)).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 28, leading: 20, bottom: 30, trailing: 20))
    }

    // MARK: Toast

    @ViewBuilder private func toast(_ palette: Palette) -> some View {
        if let toast = model.toast {
            HStack(spacing: 10) {
                Text(toast.text)
                if toast.undo != nil {
                    Button("Undo") { model.undo() }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                }
            }
            .font(Theme.font(12.5))
            .foregroundStyle(.white)
            .padding(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            .background(RoundedRectangle(cornerRadius: 10).fill(palette.toastBackground))
            .padding(.bottom, 26)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
