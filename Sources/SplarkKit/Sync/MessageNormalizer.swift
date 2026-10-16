import Foundation

/// Slack markup → the plain text the panel and the AI see (spec §6.5).
public struct MessageNormalizer: Sendable {
    public let names: [String: String]   // user ID → display name

    public init(names: [String: String] = [:]) { self.names = names }

    /// The message's text plus a `[file: name]` label per attached file.
    public func text(of message: SlackMessage) -> String {
        let files = (message.files ?? []).map { "[file: \($0.name ?? $0.title ?? "file")]" }
        return ([plain(message.text ?? "")] + files).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Bots by their bot name; people by their display name, else their ID.
    public func author(of message: SlackMessage) -> String {
        if message.botId != nil || message.subtype == "bot_message" {
            return message.botProfile?.name ?? message.username ?? message.user.flatMap { names[$0] } ?? "Bot"
        }
        return message.user.map { names[$0] ?? $0 } ?? "Unknown"
    }

    public func plain(_ markup: String) -> String {
        var out = ""
        var rest = Substring(markup)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            out += rest[..<open]
            out += replacement(for: rest[rest.index(after: open)..<close])
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return out.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacement(for token: Substring) -> String {
        let parts = token.split(separator: "|", maxSplits: 1).map(String.init)
        let target = parts.first ?? "", label = parts.count > 1 ? parts[1] : nil
        switch target.first {
        case "@":
            let id = String(target.dropFirst())
            return "@" + (names[id] ?? label ?? id)
        case "#":
            return "#" + (label ?? String(target.dropFirst()))
        case "!":
            let command = target.dropFirst()
            if ["here", "channel", "everyone"].contains(command) { return "@\(command)" }
            if command.hasPrefix("subteam^") { return label ?? "@group" }
            return label ?? String(command)
        default:
            return label ?? target
        }
    }

    /// Whether `userId` is @mentioned in the message.
    public static func mentions(_ userId: String, in message: SlackMessage) -> Bool {
        let text = message.text ?? ""
        return text.contains("<@\(userId)>") || text.contains("<@\(userId)|")
    }

    /// The author and everyone @mentioned: the names a snapshot needs.
    public static func userIds(in message: SlackMessage) -> Set<String> {
        var ids = Set(message.user.map { [$0] } ?? [])
        var rest = Substring(message.text ?? "")
        while let range = rest.range(of: "<@") {
            let id = rest[range.upperBound...].prefix { $0 != ">" && $0 != "|" }
            if !id.isEmpty { ids.insert(String(id)) }
            rest = rest[range.upperBound...]
        }
        return ids
    }
}

/// User ID → display name, looked up with `users.info` and kept for 24 hours (spec §6.2). Persisted in state.json.
public actor UserDirectory {
    public struct Entry: Codable, Sendable, Equatable {
        public let name: String
        public let fetchedAt: Date
        public init(name: String, fetchedAt: Date) { self.name = name; self.fetchedAt = fetchedAt }
    }

    public private(set) var entries: [String: Entry]
    private var unknown: [String: Date] = [:]   // IDs Slack said don't exist, and when
    private let now: @Sendable () -> Date
    private let lookup: @Sendable (String) async throws -> SlackUser
    private let maxAge: TimeInterval = 24 * 3600

    public init(now: @escaping @Sendable () -> Date = { Date() }, entries: [String: Entry] = [:],
                lookup: @escaping @Sendable (String) async throws -> SlackUser) {
        self.now = now
        self.entries = entries
        self.lookup = lookup
    }

    /// Names for `ids`, fetching any that are missing or older than a day. IDs that can't be resolved are left out.
    public func names(for ids: Set<String>) async -> [String: String] {
        for id in ids.sorted() where isStale(id) {
            do {
                entries[id] = Entry(name: try await lookup(id).displayName, fetchedAt: now())
            } catch SlackError.api {
                unknown[id] = now()   // Slack answered no (user_not_found): don't ask again today
            } catch {}                // offline, rate limited or a server error: keep what we have and try next time
        }
        return ids.reduce(into: [:]) { out, id in if let entry = entries[id] { out[id] = entry.name } }
    }

    private func isStale(_ id: String) -> Bool {
        if let failed = unknown[id], now().timeIntervalSince(failed) < maxAge { return false }
        guard let entry = entries[id] else { return true }
        return now().timeIntervalSince(entry.fetchedAt) >= maxAge
    }
}
