import Foundation
import Observation
import SplarkKit

/// What the panel asks of Slack. `Actions` is the real one; tests use a fake.
@MainActor public protocol PanelActions: AnyObject {
    func reply(to item: InboxItem, text: String) async throws
    func react(to item: InboxItem, with reaction: Reaction) async throws
    func markRead(_ items: [InboxItem]) -> Actions.UndoToken
    func undo(_ token: Actions.UndoToken)
    func open(_ item: InboxItem) async
}

extension Actions: PanelActions {}

/// The panel's behaviour, apart from its looks (spec §4.3): which row is open, reply drafts, toasts with undo,
/// and what Esc does.
@MainActor @Observable public final class PanelModel {
    public struct Toast: Equatable {
        public let text: String
        public let undo: Actions.UndoToken?
    }

    public private(set) var expanded: InboxItem.ID?
    public private(set) var focusedReply: InboxItem.ID?
    public var commentsOpen = false
    public var drafts: [ItemKey: String] = [:]   // kept when sending fails
    public private(set) var sending: Set<ItemKey> = []   // replies on their way to Slack
    public private(set) var toast: Toast?

    private let actions: PanelActions
    private let toastDuration: Duration
    private let close: () -> Void
    private let openSlack: () -> Void
    private let openSettings: () -> Void
    private var toastTask: Task<Void, Never>?

    public init(actions: PanelActions, toastDuration: Duration = .seconds(4), close: @escaping () -> Void,
                openSlack: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.actions = actions
        self.toastDuration = toastDuration
        self.close = close
        self.openSlack = openSlack
        self.openSettings = openSettings
    }

    /// A click on a row.
    public func toggle(_ item: InboxItem) {
        expanded = expanded == item.id ? nil : item.id
        focusedReply = nil
    }

    /// The toolbar's Reply: open the row with its reply field focused.
    public func startReply(_ item: InboxItem) {
        expanded = item.id
        focusedReply = item.id
    }

    /// Esc collapses an open row; with none open, it closes the panel.
    public func escape() {
        if expanded != nil {
            expanded = nil
            focusedReply = nil
        } else {
            close()
        }
    }

    /// The panel closed: an open row would only be in the way next time.
    public func panelClosed() {
        expanded = nil
        focusedReply = nil
    }

    /// Enter in the reply field. The draft stays if sending fails; a second Enter while it's on its way does nothing.
    public func send(_ item: InboxItem) async {
        guard let text = drafts[item.key], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sending.contains(item.key) else { return }
        sending.insert(item.key)
        defer { sending.remove(item.key) }
        do {
            try await actions.reply(to: item, text: text)
            drafts[item.key] = nil
            if expanded == item.id { expanded = nil }
            focusedReply = nil
        } catch {
            show(Toast(text: "Couldn't send. Try again.", undo: nil))
        }
    }

    public func react(_ item: InboxItem, _ reaction: Reaction) async {
        do { try await actions.react(to: item, with: reaction) }
        catch { show(Toast(text: "Couldn't add the reaction. Try again.", undo: nil)) }
    }

    /// The ✓ button: gone at once, with 4 seconds to undo.
    public func markRead(_ item: InboxItem) {
        if expanded == item.id { expanded = nil }
        show(Toast(text: "Marked as read", undo: actions.markRead([item])))
    }

    /// "Just comments" → ✓✓.
    public func markAllRead(_ items: [InboxItem]) {
        guard !items.isEmpty else { return }
        commentsOpen = false
        show(Toast(text: "Marked \(items.count) as read", undo: actions.markRead(items)))
    }

    public func undo() {
        guard let token = toast?.undo else { return }
        actions.undo(token)
        dismissToast()
    }

    /// Open in Slack closes the panel (spec §4.3).
    public func open(_ item: InboxItem) async {
        await actions.open(item)
        close()
    }

    public func openSlackApp() {
        openSlack()
        close()
    }

    public func showSettings() {
        openSettings()
        close()
    }

    /// A failure reported later by `Actions` (a mark-read Slack refused).
    public func showFailure(_ failure: ActionFailure) { show(Toast(text: failure.message, undo: nil)) }

    public func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    private func show(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        let duration = toastDuration
        toastTask = Task { [weak self] in
            guard (try? await Task.sleep(for: duration)) != nil else { return }
            self?.toast = nil
        }
    }
}
