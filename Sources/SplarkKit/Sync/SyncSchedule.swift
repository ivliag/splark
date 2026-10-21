import Foundation

/// When each conversation is next checked (spec §6.3, step 3). Pure: the sync engine owns the clock and the calls.
public struct SyncSchedule: Sendable {
    public struct Entry: Sendable, Equatable {
        public let id: String
        public var kind: SlackConversation.Kind
        public var due: Date
        public var lastActivity: Date?
        public var hasUnread: Bool
        public var checked: Bool
    }

    public struct Intervals: Sendable {
        public var direct: TimeInterval = 60           // IMs and MPIMs
        public var hot: TimeInterval = 60              // activity in the last 30 min, or unread now
        public var privateChannel: TimeInterval = 180
        public var publicChannel: TimeInterval = 300
        public var dormant: TimeInterval = 900         // nothing for 14 days: keeps a big DM list within Slack's limits
        public var hotWindow: TimeInterval = 1800
        public var dormantAfter: TimeInterval = 14 * 86400
        public init() {}
    }

    public struct Progress: Sendable, Equatable {
        public let checked: Int
        public let total: Int
        public var isComplete: Bool { checked >= total }

        public init(checked: Int, total: Int) {
            self.checked = checked
            self.total = total
        }
    }

    public private(set) var entries: [String: Entry] = [:]
    public let intervals: Intervals

    public init(intervals: Intervals = Intervals()) { self.intervals = intervals }

    /// New conversations are due now; ones that left are dropped; the rest keep their times.
    public mutating func setInventory(_ conversations: [String: SlackConversation.Kind], now: Date) {
        entries = entries.filter { conversations[$0.key] != nil }
        for (id, kind) in conversations {
            if entries[id] == nil {
                entries[id] = Entry(id: id, kind: kind, due: now, lastActivity: nil, hasUnread: false, checked: false)
            } else {
                entries[id]?.kind = kind
            }
        }
    }

    /// The conversation to check next: the longest overdue, DMs first among equals.
    public func next(now: Date) -> String? {
        entries.values.filter { $0.due <= now }
            .min { ($0.due, rank($0, now: now), $0.id) < ($1.due, rank($1, now: now), $1.id) }?.id
    }

    public var nextDue: Date? { entries.values.map(\.due).min() }

    public var progress: Progress {
        Progress(checked: entries.values.filter(\.checked).count, total: entries.count)
    }

    public mutating func checked(_ id: String, now: Date, lastActivity: Date?, hasUnread: Bool) {
        guard var entry = entries[id] else { return }
        entry.lastActivity = lastActivity
        entry.hasUnread = hasUnread
        entry.checked = true
        entry.due = now.addingTimeInterval(interval(entry, now: now))
        entries[id] = entry
    }

    public mutating func postpone(_ id: String, until: Date) { entries[id]?.due = until }

    /// Check this one before anything else.
    public mutating func wake(_ id: String) { entries[id]?.due = .distantPast }

    /// Slack's badge changed: something arrived for the user, most likely in a DM or a busy conversation.
    public mutating func wakeDirect(now: Date) {
        for (id, entry) in entries where entry.kind == .im || entry.kind == .mpim || isHot(entry, now: now) {
            entries[id]?.due = .distantPast
        }
    }

    func interval(_ entry: Entry, now: Date) -> TimeInterval {
        if isHot(entry, now: now) { return intervals.hot }
        if let last = entry.lastActivity, now.timeIntervalSince(last) > intervals.dormantAfter { return intervals.dormant }
        switch entry.kind {
        case .im, .mpim: return intervals.direct
        case .privateChannel: return intervals.privateChannel
        case .publicChannel: return intervals.publicChannel
        }
    }

    private func isHot(_ entry: Entry, now: Date) -> Bool {
        entry.hasUnread || entry.lastActivity.map { now.timeIntervalSince($0) < intervals.hotWindow } ?? false
    }

    private func rank(_ entry: Entry, now: Date) -> Int {
        if entry.kind == .im || isHot(entry, now: now) { return 0 }
        switch entry.kind {
        case .mpim: return 1
        case .privateChannel: return 2
        default: return 3
        }
    }
}
