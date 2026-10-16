import Foundation

/// Slack message timestamps ("1739999999.000100"). They compare as numbers: a Double loses the last digits.
public enum SlackTS {
    public static let zero = "0000000000.000000"

    private static func parts(_ ts: String) -> (Int, Int) {
        let split = ts.split(separator: ".", maxSplits: 1)
        let micros = split.count > 1 ? String(split[1].prefix(6)).padding(toLength: 6, withPad: "0", startingAt: 0) : "0"
        return (Int(split.first ?? "") ?? 0, Int(micros) ?? 0)
    }

    public static func isAfter(_ a: String, _ b: String) -> Bool { parts(a) > parts(b) }

    /// The latest of the given timestamps, ignoring nils.
    public static func latest(_ values: String?...) -> String? { latest(values) }

    public static func latest(_ values: [String?]) -> String? {
        values.compactMap { $0 }.max { isAfter($1, $0) }
    }

    /// `last_read` of `"0000000000.000000"` (or none) means the conversation was never opened.
    public static func isZero(_ ts: String?) -> Bool { ts.map { parts($0) == (0, 0) } ?? true }

    public static func date(_ ts: String) -> Date {
        let (seconds, micros) = parts(ts)
        return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(micros) / 1_000_000)
    }

    public static func ts(_ date: Date) -> String { String(format: "%.6f", date.timeIntervalSince1970) }

    /// One microsecond earlier: the `oldest` that still includes `ts` (Slack's `oldest` is exclusive).
    public static func justBefore(_ ts: String) -> String {
        let (seconds, micros) = parts(ts)
        return micros > 0 ? String(format: "%d.%06d", seconds, micros - 1) : String(format: "%d.%06d", seconds - 1, 999_999)
    }
}

/// One inbox entry's identity: a conversation, or one thread in it.
public struct ItemKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let teamId: String
    public let channelId: String
    public let threadTs: String?

    public init(teamId: String, channelId: String, threadTs: String? = nil) {
        self.teamId = teamId
        self.channelId = channelId
        self.threadTs = threadTs
    }

    public var description: String { "\(teamId)/\(channelId)" + (threadTs.map { "/\($0)" } ?? "") }
}

/// The kinds the AI and the panel distinguish (spec §7.3).
public enum SnapshotKind: String, Codable, Sendable { case dm, groupDM = "group_dm", channel, thread }

public struct SnapshotMessage: Codable, Sendable, Equatable {
    public let ts: String
    public let authorId: String?
    public let author: String
    public let text: String
    public let mentionsMe: Bool

    public init(ts: String, authorId: String?, author: String, text: String, mentionsMe: Bool) {
        self.ts = ts
        self.authorId = authorId
        self.author = author
        self.text = text
        self.mentionsMe = mentionsMe
    }
}

/// What the sync engine knows about one unread conversation or thread. Lives in memory only (spec §8).
public struct ConversationSnapshot: Sendable, Equatable, Identifiable {
    public var id: ItemKey { key }
    public let key: ItemKey
    public let kind: SnapshotKind
    public let title: String               // "Marta Ruiz", "#eng", "marta, leo"; for threads, the conversation's title
    public let unread: [SnapshotMessage]   // oldest first, never empty
    public let context: [SnapshotMessage]  // up to 3 earlier messages, oldest first
    public let moreUnread: Bool            // older unread messages were left out

    public init(key: ItemKey, kind: SnapshotKind, title: String, unread: [SnapshotMessage], context: [SnapshotMessage], moreUnread: Bool) {
        precondition(!unread.isEmpty, "a snapshot has at least one unread message")
        self.key = key
        self.kind = kind
        self.title = title
        self.unread = unread
        self.context = context
        self.moreUnread = moreUnread
    }

    public var newestTs: String { unread[unread.count - 1].ts }
    public var mentionsMe: Bool { unread.contains { $0.mentionsMe } }
    /// DMs, group DMs, threads the user is in, and @mentions: aimed at the user (spec §7.3).
    public var isDirect: Bool { kind != .channel || mentionsMe }
}

public enum ConversationTitle {
    /// "Marta Ruiz" for a DM, "marta, leo" for a group DM (from Slack's `mpdm-a--b--c-1` name), "#eng" for a channel.
    public static func make(_ conversation: SlackConversation, names: [String: String], myHandle: String?) -> String {
        switch conversation.kind {
        case .im:
            return conversation.user.map { names[$0] ?? $0 } ?? conversation.id
        case .mpim:
            guard let name = conversation.name, name.hasPrefix("mpdm-") else { return conversation.name ?? conversation.id }
            var handles = name.dropFirst("mpdm-".count).components(separatedBy: "--")
            if let last = handles.last, let dash = last.lastIndex(of: "-"), Int(last[last.index(after: dash)...]) != nil {
                handles[handles.count - 1] = String(last[..<dash])
            }
            return handles.filter { $0 != myHandle }.joined(separator: ", ")
        case .privateChannel, .publicChannel:
            return "#" + (conversation.name ?? conversation.id)
        }
    }
}
