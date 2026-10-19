import AppKit
import Foundation
import Observation

/// The Slack connection and sync engine behind one workspace's items.
public struct ActionTarget: Sendable {
    public let slack: SlackAPI
    public let engine: SyncEngine

    public init(slack: SlackAPI, engine: SyncEngine) {
        self.slack = slack
        self.engine = engine
    }
}

public enum ActionError: Error, Equatable {
    case notConnected
    case offline
    case slack(String)
}

/// Shown as a toast (spec §9). Each failure is its own value, so the same one twice still reaches the toast.
public struct ActionFailure: Sendable, Equatable {
    public let id = UUID()
    public let key: ItemKey
    public let message: String
}

/// `slack://channel?team=T&id=C&message=ts`, plus `&thread_ts=` in threads: undocumented but widely used (spec §6.4).
public enum DeepLink {
    public static func slack(teamId: String, channelId: String, messageTs: String, threadTs: String?) -> URL {
        var c = URLComponents()
        c.scheme = "slack"
        c.host = "channel"
        c.queryItems = [URLQueryItem(name: "team", value: teamId), URLQueryItem(name: "id", value: channelId),
                        URLQueryItem(name: "message", value: messageTs)] + (threadTs.map { [URLQueryItem(name: "thread_ts", value: $0)] } ?? [])
        return c.url!
    }
}

/// What the panel does in Slack (spec §4.3): reply, react, mark read (with a 4-second undo), open.
/// Each shows at once and rolls back if Slack refuses.
@MainActor @Observable
public final class Actions {
    public struct UndoToken: Hashable, Sendable {
        let id = UUID()
        public init() {}
    }

    public private(set) var lastFailure: ActionFailure?

    private let inbox: InboxStore
    private let targets: @MainActor (String) -> ActionTarget?
    private let onUpdate: @MainActor (SyncUpdate) async -> Void
    private let undoWindow: Duration
    private let openURL: @MainActor (URL) -> Bool
    private var pending: [UndoToken: [ItemKey: String]] = [:]   // marked read, waiting out the undo window

    /// `onUpdate` receives what the sync engine changed after a mark-read; by default it goes to `inbox`.
    public init(inbox: InboxStore, targets: @escaping @MainActor (String) -> ActionTarget?,
                onUpdate: (@MainActor (SyncUpdate) async -> Void)? = nil, undoWindow: Duration = .seconds(4),
                open: @escaping @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.inbox = inbox
        self.targets = targets
        self.onUpdate = onUpdate ?? { [inbox] in inbox.apply($0) }
        self.undoWindow = undoWindow
        self.openURL = open
    }

    /// In the thread of the item's message for channels and threads; directly in DMs and group DMs.
    /// Slack's read marker doesn't move, so the item stays, marked "replied".
    public func reply(to item: InboxItem, text: String) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let target = targets(item.key.teamId) else { throw ActionError.notConnected }
        let threadTs = item.kind == .dm || item.kind == .groupDM ? nil : item.key.threadTs ?? item.anchorTs
        inbox.markReplied(item.key)
        do {
            let posted = try await target.slack.chatPostMessage(channel: item.key.channelId, text: text, threadTs: threadTs)
            await target.engine.didReply(channelId: item.key.channelId, threadTs: threadTs, ts: posted.ts)
        } catch {
            inbox.unmarkReplied(item.key)
            throw Self.actionError(error)
        }
    }

    public func react(to item: InboxItem, with reaction: Reaction) async throws {
        guard let target = targets(item.key.teamId) else { throw ActionError.notConnected }
        inbox.addReaction(reaction, to: item.id)
        do {
            try await target.slack.reactionsAdd(channel: item.key.channelId, timestamp: item.anchorTs, name: reaction.rawValue)
        } catch SlackError.api("already_reacted") {
        } catch {
            inbox.removeReaction(reaction, from: item.id)
            throw Self.actionError(error)
        }
    }

    /// Hides the items now; Slack is told once the undo window has passed.
    @discardableResult
    public func markRead(_ items: [InboxItem]) -> UndoToken {
        let token = UndoToken()
        var marks: [ItemKey: String] = [:]
        for item in items {
            marks[item.key] = SlackTS.latest(marks[item.key], inbox.snapshot(for: item.key)?.newestTs ?? item.newestTs)
        }
        for (key, through) in marks { inbox.hide(key, through: through) }
        pending[token] = marks
        let window = undoWindow
        Task { [weak self] in
            try? await Task.sleep(for: window)
            await self?.commit(token)
        }
        return token
    }

    /// "Just comments" → mark all read.
    @discardableResult
    public func markAllCommentsRead() -> UndoToken {
        markRead(inbox.items.filter { $0.level == .fyi })
    }

    public func undo(_ token: UndoToken) {
        guard let marks = pending.removeValue(forKey: token) else { return }
        for key in marks.keys { inbox.unhide(key) }
    }

    /// Sends every mark-read still in its undo window, for example when Splark quits.
    public func commitPendingReads() async {
        for token in Array(pending.keys) { await commit(token) }
    }

    /// Opens the message in the Slack app, or its permalink in the browser when that fails.
    public func open(_ item: InboxItem) async {
        if openURL(DeepLink.slack(teamId: item.key.teamId, channelId: item.key.channelId, messageTs: item.anchorTs, threadTs: item.key.threadTs)) { return }
        guard let target = targets(item.key.teamId) else { return }
        do { _ = openURL(try await target.slack.chatGetPermalink(channel: item.key.channelId, messageTs: item.anchorTs)) }
        catch { lastFailure = ActionFailure(key: item.key, message: "Couldn't open Slack.") }
    }

    private func commit(_ token: UndoToken) async {
        guard let marks = pending.removeValue(forKey: token) else { return }
        for (key, through) in marks {
            guard let target = targets(key.teamId) else { inbox.unhide(key); continue }
            do {
                if key.threadTs == nil { try await target.slack.conversationsMark(channel: key.channelId, ts: through) }   // threads have no read marker
                await onUpdate(await target.engine.markedRead(key, through: through))
            } catch {
                inbox.unhide(key)
                lastFailure = ActionFailure(key: key, message: "Couldn't mark it as read. Try again.")
            }
        }
    }

    private static func actionError(_ error: Error) -> ActionError {
        switch error {
        case let error as ActionError: error
        case SlackError.api(let code): .slack(code)
        case is URLError: .offline
        default: .slack("\(error)")
        }
    }
}
