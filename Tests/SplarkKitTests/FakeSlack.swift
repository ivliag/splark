import Foundation
@testable import SplarkKit

/// An in-memory Slack workspace for the sync engine and the actions. Records every call as "method channel".
final class FakeSlack: SlackAPI, @unchecked Sendable {
    struct Channel {
        var conversation: SlackConversation
        var messages: [SlackMessage] = []   // top-level messages, oldest first
        var lastRead: String?
        var unreadCountDisplay: Int?
    }

    private let lock = NSLock()
    private var channels: [String: Channel] = [:]
    private var threads: [String: [SlackMessage]] = [:]   // "C1/1.0" → replies, oldest first (not the parent)
    private var users: [String: SlackUser] = [:]
    private var searches: [String: [SlackSearchResult.Match]] = [:]
    private var failures: [String: Error] = [:]
    private var log: [String] = []
    private var nextTs = 1_800_100_000
    private(set) var posted: [(channel: String, text: String, threadTs: String?)] = []
    private(set) var reactions: [(channel: String, ts: String, name: String)] = []

    let me: String
    let team: String
    /// Runs inside every call, before it answers: lets a test act while the engine waits on Slack.
    nonisolated(unsafe) var onCall: (@Sendable (String) async -> Void)?

    init(me: String = "U1", team: String = "T1") {
        self.me = me
        self.team = team
    }

    // MARK: Setting up the workspace

    func addChannel(_ id: String, kind: SlackConversation.Kind, name: String? = nil, user: String? = nil,
                    lastRead: String? = nil, unreadCountDisplay: Int? = nil) {
        let conversation = SlackConversation(id: id, name: name, user: user, isIm: kind == .im, isMpim: kind == .mpim,
                                             isPrivate: kind == .privateChannel || kind == .mpim, isChannel: kind == .publicChannel || kind == .privateChannel,
                                             isArchived: false, lastRead: nil, unreadCountDisplay: nil)
        lock.withLock { channels[id] = Channel(conversation: conversation, lastRead: lastRead, unreadCountDisplay: unreadCountDisplay) }
    }

    func removeChannel(_ id: String) { lock.withLock { _ = channels.removeValue(forKey: id) } }

    func post(_ channel: String, _ message: SlackMessage) {
        lock.withLock { channels[channel]?.messages.append(message) }
    }

    func reply(_ channel: String, thread: String, _ message: SlackMessage) {
        lock.withLock { threads["\(channel)/\(thread)", default: []].append(message) }
    }

    func setLastRead(_ channel: String, _ ts: String?, unreadCountDisplay: Int? = nil) {
        lock.withLock {
            channels[channel]?.lastRead = ts
            channels[channel]?.unreadCountDisplay = unreadCountDisplay
        }
    }

    func addUser(_ id: String, _ name: String) {
        lock.withLock { users[id] = SlackUser(id: id, name: nil, realName: nil, profile: .init(displayName: name, realName: nil)) }
    }

    func setSearch(_ query: String, _ hits: [(channel: String, ts: String, threadTs: String?)]) {
        lock.withLock {
            searches[query] = hits.map { hit in
                let link = "https://x.slack.com/archives/\(hit.channel)/p\(hit.ts.replacingOccurrences(of: ".", with: ""))"
                    + (hit.threadTs.map { "?thread_ts=\($0)&cid=\(hit.channel)" } ?? "")
                return SlackSearchResult.Match(channel: .init(id: hit.channel, name: nil), ts: hit.ts, user: nil, text: nil, permalink: link)
            }
        }
    }

    /// Every call to `key` ("method" or "method channel") throws `error` until cleared with nil.
    func fail(_ key: String, with error: Error?) { lock.withLock { failures[key] = error } }

    var calls: [String] { lock.withLock { log } }
    func clearCalls() { lock.withLock { log.removeAll() } }
    func lastRead(_ channel: String) -> String? { lock.withLock { channels[channel]?.lastRead } }

    private func record(_ method: String, _ channel: String? = nil) async throws {
        let key = channel.map { "\(method) \($0)" } ?? method
        await onCall?(key)
        try lock.withLock {
            log.append(key)
            if let error = failures[key] ?? failures[method] { throw error }
        }
    }

    // MARK: SlackAPI

    func authTest() async throws -> SlackAuthTest {
        try await record("auth.test")
        return SlackAuthTest(userId: me, user: "ivan", teamId: team, team: "Lumen", url: "https://lumen.slack.com/")
    }

    func allConversations() async throws -> [SlackConversation] {
        try await record("users.conversations")
        return lock.withLock { channels.values.map(\.conversation).sorted { $0.id < $1.id } }
    }

    func conversationsInfo(_ channel: String) async throws -> SlackConversation {
        try await record("conversations.info", channel)
        return try lock.withLock {
            guard let c = channels[channel] else { throw SlackError.api("channel_not_found") }
            let v = c.conversation
            return SlackConversation(id: v.id, name: v.name, user: v.user, isIm: v.isIm, isMpim: v.isMpim, isPrivate: v.isPrivate,
                                     isChannel: v.isChannel, isArchived: v.isArchived, lastRead: c.lastRead ?? SlackTS.zero,
                                     unreadCountDisplay: c.unreadCountDisplay)
        }
    }

    func conversationsHistory(_ channel: String, oldest: String?, latest: String?, inclusive: Bool, limit: Int) async throws -> SlackHistory {
        try await record("conversations.history", channel)
        if let oldest, SlackTS.isZero(oldest) { throw SlackError.api("invalid_ts_oldest") }   // as real Slack does (spike 1)
        return try lock.withLock {
            guard let c = channels[channel] else { throw SlackError.api("channel_not_found") }
            let matching = c.messages.filter { m in
                (oldest.map { SlackTS.isAfter(m.ts, $0) } ?? true)
                    && (latest.map { inclusive ? !SlackTS.isAfter(m.ts, $0) : SlackTS.isAfter($0, m.ts) } ?? true)
            }
            let newestFirst = matching.reversed()
            return SlackHistory(messages: Array(newestFirst.prefix(limit)), hasMore: newestFirst.count > limit, responseMetadata: nil)
        }
    }

    func conversationsReplies(_ channel: String, ts: String, oldest: String?, limit: Int) async throws -> SlackHistory {
        try await record("conversations.replies", channel)
        return try lock.withLock {
            guard let parent = channels[channel]?.messages.first(where: { $0.ts == ts }) else { throw SlackError.api("thread_not_found") }
            let replies = (threads["\(channel)/\(ts)"] ?? []).filter { r in oldest.map { SlackTS.isAfter(r.ts, $0) } ?? true }
            return SlackHistory(messages: [parent] + replies.prefix(limit), hasMore: replies.count > limit, responseMetadata: nil)
        }
    }

    func usersInfo(_ user: String) async throws -> SlackUser {
        try await record("users.info")
        return try lock.withLock {
            guard let u = users[user] else { throw SlackError.api("user_not_found") }
            return u
        }
    }

    func searchMessages(_ query: String, count: Int) async throws -> SlackSearchResult {
        try await record("search.messages")
        let matches = lock.withLock { Array((searches[query] ?? []).prefix(count)) }
        return SlackSearchResult(messages: .init(total: matches.count, matches: matches))
    }

    func chatPostMessage(channel: String, text: String, threadTs: String?) async throws -> SlackPostedMessage {
        try await record("chat.postMessage", channel)
        return lock.withLock {
            nextTs += 1
            posted.append((channel, text, threadTs))
            return SlackPostedMessage(channel: channel, ts: "\(nextTs).000000")
        }
    }

    func reactionsAdd(channel: String, timestamp: String, name: String) async throws {
        try await record("reactions.add", channel)
        lock.withLock { reactions.append((channel, timestamp, name)) }
    }

    func conversationsMark(channel: String, ts: String) async throws {
        try await record("conversations.mark", channel)
        lock.withLock { channels[channel]?.lastRead = ts }
    }

    func chatGetPermalink(channel: String, messageTs: String) async throws -> URL {
        try await record("chat.getPermalink", channel)
        return URL(string: "https://lumen.slack.com/archives/\(channel)/p\(messageTs.replacingOccurrences(of: ".", with: ""))")!
    }
}
