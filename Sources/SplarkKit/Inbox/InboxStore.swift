import Foundation
import Observation

/// The panel's quick reactions (spec §4.3).
public enum Reaction: String, CaseIterable, Sendable {
    case eyes
    case whiteCheckMark = "white_check_mark"
    case thumbsUp = "+1"

    public var emoji: String {
        switch self {
        case .eyes: "👀"
        case .whiteCheckMark: "✅"
        case .thumbsUp: "👍"
        }
    }
}

/// One row in the panel.
public struct InboxItem: Identifiable, Sendable, Equatable {
    public struct ID: Hashable, Sendable {
        public let key: ItemKey
        public let slot: Int   // a conversation can hold two items
    }

    public let id: ID
    public var key: ItemKey { id.key }
    public let level: TriageLevel
    public let lead: String
    public let rest: String
    public let reason: String
    public let anchorTs: String
    public let byAI: Bool
    public let kind: SnapshotKind
    public let title: String               // "Marta Ruiz", "#eng"
    public let source: String              // the meta line: "Marta Ruiz", "#eng", "thread in #eng"
    public let workspaceLabel: String?     // only for workspaces after the first connected
    public let isDirect: Bool
    public let newestTs: String
    public let messages: [SnapshotMessage] // the last 10 unread, oldest first
    public let earlier: Int                // "and N earlier"
    public let moreEarlier: Bool           // even more were left out of the snapshot
    public let replied: Bool
    public let reactions: [Reaction]

    public var newest: Date { SlackTS.date(newestTs) }
    public var replyPlaceholder: String { kind == .dm || kind == .groupDM ? "Message \(title)" : "Reply in thread" }
}

/// The menu bar and the panel header (spec §4.2, §4.3).
public struct InboxSummary: Sendable, Equatable {
    public let needYou: Int        // needs-action and question items: the number next to the spark
    public let spark: SparkLevel   // the most important level waiting
    public let headline: String    // "3 need you", "Nothing needs you", "All caught up"
    public let comments: Int       // "Just comments · N conversations"
}

/// One sorted list across workspaces (spec §5.2): sync snapshots plus their summaries, minus excluded channels,
/// with the optimistic states of the panel's actions.
@MainActor @Observable
public final class InboxStore {
    public private(set) var items: [InboxItem] = []

    private struct MessageRef: Hashable { let key: ItemKey; let ts: String }

    private var snapshots: [ItemKey: ConversationSnapshot] = [:]
    private var results: [ItemKey: TriageResult] = [:]
    private var workspaces: [Workspace] = []
    private var excluded: [String: Set<String>] = [:]
    private var hidden: [ItemKey: String] = [:]          // marked read in Splark, through this ts
    private var repliedAt: [ItemKey: String] = [:]       // replied when this was the newest message
    private var reactions: [MessageRef: [Reaction]] = [:]

    public init() {}

    public var summary: InboxSummary {
        let needYou = items.filter { $0.level != .fyi }
        let spark: SparkLevel = needYou.contains { $0.level == .action } ? .bright : needYou.isEmpty ? .dimmed : .brighter
        let headline = items.isEmpty ? "All caught up" : needYou.isEmpty ? "Nothing needs you"
            : "\(needYou.count) need\(needYou.count == 1 ? "s" : "") you"
        return InboxSummary(needYou: needYou.count, spark: spark, headline: headline, comments: items.count - needYou.count)
    }

    public func snapshot(for key: ItemKey) -> ConversationSnapshot? { snapshots[key] }

    /// In the order they were connected: the first is the one whose name the panel leaves out.
    public func setWorkspaces(_ workspaces: [Workspace]) {
        self.workspaces = workspaces
        rebuild()
    }

    public func setExcluded(_ channels: Set<String>, teamId: String) {
        excluded[teamId] = channels
        rebuild()
    }

    public func apply(_ update: SyncUpdate) {
        for key in update.removed {
            snapshots[key] = nil
            results[key] = nil
            hidden[key] = nil
            repliedAt[key] = nil
            reactions = reactions.filter { $0.key.key != key }
        }
        for snapshot in update.upserted.values {
            snapshots[snapshot.key] = snapshot
            if let through = hidden[snapshot.key], SlackTS.isAfter(snapshot.newestTs, through) { hidden[snapshot.key] = nil }
        }
        rebuild()
    }

    public func apply(_ results: [TriageResult]) {
        for result in results where snapshots[result.key] != nil { self.results[result.key] = result }
        rebuild()
    }

    // MARK: Optimistic states for Actions

    public func hide(_ key: ItemKey, through ts: String) {
        hidden[key] = ts
        rebuild()
    }

    public func unhide(_ key: ItemKey) {
        hidden[key] = nil
        rebuild()
    }

    public func markReplied(_ key: ItemKey) {
        repliedAt[key] = snapshots[key]?.newestTs
        rebuild()
    }

    public func unmarkReplied(_ key: ItemKey) {
        repliedAt[key] = nil
        rebuild()
    }

    public func addReaction(_ reaction: Reaction, to id: InboxItem.ID) {
        guard let ref = ref(id), !(reactions[ref] ?? []).contains(reaction) else { return }
        reactions[ref, default: []].append(reaction)
        rebuild()
    }

    public func removeReaction(_ reaction: Reaction, from id: InboxItem.ID) {
        guard let ref = ref(id) else { return }
        reactions[ref]?.removeAll { $0 == reaction }
        rebuild()
    }

    private func ref(_ id: InboxItem.ID) -> MessageRef? {
        items.first { $0.id == id }.map { MessageRef(key: $0.key, ts: $0.anchorTs) }
    }

    // MARK: Building the list

    private func rebuild() {
        let primary = workspaces.first?.teamId
        let names = Dictionary(workspaces.map { ($0.teamId, $0.name) }, uniquingKeysWith: { a, _ in a })
        var built: [InboxItem] = []
        for (key, snapshot) in snapshots {
            if excluded[key.teamId]?.contains(key.channelId) == true { continue }
            if let through = hidden[key], !SlackTS.isAfter(snapshot.newestTs, through) { continue }
            // An older summary stays until the new one arrives, unless the heuristic ranks the new messages higher
            // (summaries may be paused for hours). The heuristic also covers conversations never summarised.
            let heuristic = TriagePrompt.heuristic(snapshot)
            var triaged = results[key]?.items ?? [heuristic]
            if let result = results[key], result.newestTs != snapshot.newestTs,
               let top = result.items.map(\.level).min(), heuristic.level < top {
                triaged = [heuristic]
            }
            let shown = snapshot.unread.suffix(10)
            for (slot, item) in triaged.enumerated() {
                built.append(InboxItem(
                    id: .init(key: key, slot: slot), level: item.level, lead: item.lead, rest: item.rest, reason: item.reason,
                    anchorTs: item.anchorTs, byAI: item.byAI, kind: snapshot.kind, title: snapshot.title,
                    source: snapshot.kind == .thread ? "thread in \(snapshot.title)" : snapshot.title,
                    workspaceLabel: key.teamId == primary ? nil : names[key.teamId], isDirect: snapshot.isDirect,
                    newestTs: snapshot.newestTs, messages: Array(shown), earlier: snapshot.unread.count - shown.count,
                    moreEarlier: snapshot.moreUnread, replied: repliedAt[key] == snapshot.newestTs,
                    reactions: reactions[MessageRef(key: key, ts: item.anchorTs)] ?? []))
            }
        }
        // Level, then DMs and @mentions, then newest first (spec §4.3).
        items = built.sorted { a, b in
            if a.level != b.level { return a.level < b.level }
            if a.isDirect != b.isDirect { return a.isDirect }
            if a.newestTs != b.newestTs { return SlackTS.isAfter(a.newestTs, b.newestTs) }
            return (a.key.description, a.id.slot) < (b.key.description, b.id.slot)
        }
    }
}
