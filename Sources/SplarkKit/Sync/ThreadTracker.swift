import Foundation

/// A thread the user is in. Slack has no read state for threads, so Splark keeps its own line (spec §6.3, step 5).
public struct ThreadWatch: Codable, Sendable, Equatable {
    public let channelId: String
    public let threadTs: String
    public var seenThrough: String   // replies after this are unread
    public var newestSeen: String?   // the newest reply a check has fetched
    public var lastActivity: Date    // the thread's latest known activity; forgotten 7 days after this
    public var due: Date
}

/// The threads the user started, replied to or was mentioned in. Persisted in state.json (IDs and timestamps only).
public struct ThreadTracker: Codable, Sendable, Equatable {
    public static let keepFor: TimeInterval = 7 * 86400
    public private(set) var watches: [String: ThreadWatch] = [:]

    public init() {}

    private static func key(_ channelId: String, _ threadTs: String) -> String { "\(channelId)/\(threadTs)" }

    public func watch(channelId: String, threadTs: String) -> ThreadWatch? { watches[Self.key(channelId, threadTs)] }

    /// Starts watching, due now. An existing watch keeps its line and its schedule: they never move back.
    /// `activity` is when the thread was last active, as far as the caller knows.
    public mutating func watch(channelId: String, threadTs: String, seenThrough: String, activity: Date, now: Date) {
        let key = Self.key(channelId, threadTs)
        if var existing = watches[key] {
            existing.lastActivity = max(existing.lastActivity, activity)
            watches[key] = existing
        } else {
            watches[key] = ThreadWatch(channelId: channelId, threadTs: threadTs, seenThrough: seenThrough, newestSeen: nil,
                                       lastActivity: activity, due: now)
        }
    }

    /// Whether a reply at `ts` is newer than anything this watch has read or fetched (false when not watched).
    public func isUnseen(_ ts: String, channelId: String, threadTs: String) -> Bool {
        guard let watch = watch(channelId: channelId, threadTs: threadTs) else { return false }
        return SlackTS.isAfter(ts, SlackTS.latest(watch.seenThrough, watch.newestSeen) ?? watch.seenThrough)
    }

    /// The user replied (in Slack or from Splark), so everything before the reply is read.
    public mutating func userReplied(channelId: String, threadTs: String, ts: String, now: Date) {
        watch(channelId: channelId, threadTs: threadTs, seenThrough: ts, activity: SlackTS.date(ts), now: now)
        clear(channelId: channelId, threadTs: threadTs, through: ts)
    }

    /// Marked read in Splark, or expired: nothing up to `ts` is unread.
    public mutating func clear(channelId: String, threadTs: String, through ts: String) {
        let key = Self.key(channelId, threadTs)
        guard let watch = watches[key] else { return }
        watches[key]?.seenThrough = SlackTS.latest(watch.seenThrough, ts) ?? ts
    }

    /// Slack's badge went clear: the user has read everything up to now, in every thread.
    public mutating func clearAll(through ts: String) {
        for (key, watch) in watches { watches[key]?.seenThrough = SlackTS.latest(watch.seenThrough, ts) ?? ts }
    }

    /// Watches due for a `conversations.replies` check, the longest overdue first.
    public func due(now: Date) -> [ThreadWatch] {
        watches.values.filter { $0.due <= now }.sorted { ($0.due, $0.threadTs) < ($1.due, $1.threadTs) }
    }

    public var nextDue: Date? { watches.values.map(\.due).min() }

    /// After a check that fetched replies up to `newestReply`. Busy threads (a reply in the last 30 min) are
    /// checked every minute, others every 3 minutes.
    public mutating func checked(channelId: String, threadTs: String, newestReply: String?, now: Date) {
        let key = Self.key(channelId, threadTs)
        guard var watch = watches[key] else { return }
        if let newestReply {
            watch.newestSeen = SlackTS.latest(watch.newestSeen, newestReply)
            watch.lastActivity = max(watch.lastActivity, SlackTS.date(newestReply))
        }
        watch.due = now.addingTimeInterval(now.timeIntervalSince(watch.lastActivity) < 1800 ? 60 : 180)
        watches[key] = watch
    }

    public mutating func postpone(channelId: String, threadTs: String, until: Date) {
        watches[Self.key(channelId, threadTs)]?.due = until
    }

    public mutating func remove(channelId: String, threadTs: String) {
        watches.removeValue(forKey: Self.key(channelId, threadTs))
    }

    public mutating func wake(channelId: String, threadTs: String) {
        watches[Self.key(channelId, threadTs)]?.due = .distantPast
    }

    public mutating func wakeAll() {
        for key in watches.keys { watches[key]?.due = .distantPast }
    }

    public mutating func prune(now: Date) {
        watches = watches.filter { now.timeIntervalSince($0.value.lastActivity) <= Self.keepFor }
    }
}
