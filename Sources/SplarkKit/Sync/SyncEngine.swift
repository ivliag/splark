import Foundation

/// What the user needs to know about a workspace's sync (spec §6.3 step 7, §9).
public enum SyncProblem: Sendable, Equatable {
    case offline(retryAt: Date)   // "Offline, showing last results"
    case reauthorize              // the refresh token was refused: stopped until the user clicks Allow again
    case tokenRevoked             // stopped

    public var stopsSync: Bool { self == .reauthorize || self == .tokenRevoked }
}

public struct SyncStatus: Sendable, Equatable {
    public var problem: SyncProblem?
    public var missingScope = false   // "Reconnect to grant new permissions"; syncing goes on, so it outlives other problems
    public var progress = SyncSchedule.Progress(checked: 0, total: 0)   // "Catching up… 120 of 300 conversations"
    public var lastSuccess: Date?
}

/// Snapshots that appeared or changed, and ones that went away.
public struct SyncUpdate: Sendable, Equatable {
    public var upserted: [ItemKey: ConversationSnapshot] = [:]
    public var removed: Set<ItemKey> = []

    public init() {}

    public var isEmpty: Bool { upserted.isEmpty && removed.isEmpty }

    public mutating func upsert(_ snapshot: ConversationSnapshot) {
        removed.remove(snapshot.key)
        upserted[snapshot.key] = snapshot
    }

    public mutating func remove(_ key: ItemKey) {
        upserted.removeValue(forKey: key)
        removed.insert(key)
    }

    public mutating func merge(_ other: SyncUpdate) {
        other.removed.forEach { remove($0) }
        other.upserted.values.forEach { upsert($0) }
    }
}

/// Finds one workspace's unread conversations (spec §6.3). `step()` does the most overdue piece of work
/// and returns; the app calls it in a loop and sleeps until `nextWake` when nothing is due.
public actor SyncEngine {
    public struct Config: Sendable {
        public var inventoryInterval: TimeInterval = 1800
        public var unreadHorizon: TimeInterval = 14 * 86400   // older unread messages are left out
        public var historyLimit = 40
        public var contextCount = 3
        public var maxBackoff: TimeInterval = 300
        public var schedule = SyncSchedule.Intervals()
        public init() {}
    }

    public struct Step: Sendable {
        public let update: SyncUpdate
        public let didWork: Bool
        public let nextWake: Date?   // nil: stopped
    }

    static let shownSubtypes: Set<String?> = [nil, "bot_message", "thread_broadcast", "file_share", "me_message"]
    static let revokedErrors: Set<String> = ["token_revoked", "invalid_auth", "account_inactive", "not_authed"]
    static let goneErrors: Set<String> = ["channel_not_found", "not_in_channel", "is_archived", "thread_not_found"]

    public let workspace: Workspace
    private let slack: SlackAPI
    private let names: UserDirectory
    private let config: Config
    private let now: @Sendable () -> Date
    private var excluded: Set<String>
    private var schedule: SyncSchedule
    private var inventory: [String: SlackConversation] = [:]
    private var inventoryDue = Date.distantPast
    private var readThrough: [String: String] = [:]   // marked read in Splark; Slack's last_read may lag behind
    private var failures = 0
    public private(set) var snapshots: [ItemKey: ConversationSnapshot] = [:]
    public private(set) var status = SyncStatus()

    public init(workspace: Workspace, slack: SlackAPI, names: UserDirectory, excluded: Set<String> = [],
                config: Config = Config(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.workspace = workspace
        self.slack = slack
        self.names = names
        self.excluded = excluded
        self.config = config
        self.now = now
        self.schedule = SyncSchedule(intervals: config.schedule)
    }

    private enum Job { case inventory, conversation(String) }

    public func step() async -> Step {
        let now = now()
        if let problem = status.problem, problem.stopsSync { return Step(update: SyncUpdate(), didWork: false, nextWake: nil) }
        if case .offline(let retryAt)? = status.problem, now < retryAt { return Step(update: SyncUpdate(), didWork: false, nextWake: retryAt) }
        guard let job = nextJob(now: now) else { return Step(update: SyncUpdate(), didWork: false, nextWake: nextWake) }
        var update: SyncUpdate
        do {
            update = try await run(job, now: now)
            failures = 0
            if case .offline? = status.problem { status.problem = nil }
            status.lastSuccess = self.now()
        } catch {
            update = handle(error, job: job, now: self.now())
        }
        status.progress = schedule.progress
        return Step(update: update, didWork: true, nextWake: status.problem?.stopsSync == true ? nil : nextWake)
    }

    /// Marked read in Splark: hide it now, and keep it hidden until Slack's read marker catches up.
    /// Anything newer than `ts` that arrived meanwhile stays.
    public func markedRead(_ key: ItemKey, through ts: String) -> SyncUpdate {
        readThrough[key.channelId] = SlackTS.latest(readThrough[key.channelId], ts)
        guard let snapshot = snapshots[key], SlackTS.isAfter(snapshot.newestTs, ts) else { return removing(key) }
        let read = snapshot.unread.filter { !SlackTS.isAfter($0.ts, ts) }
        return upserting(ConversationSnapshot(key: key, kind: snapshot.kind, title: snapshot.title,
                                              unread: snapshot.unread.filter { SlackTS.isAfter($0.ts, ts) },
                                              context: Array((snapshot.context + read).suffix(config.contextCount)), moreUnread: false))
    }

    public func setExcluded(_ ids: Set<String>) -> SyncUpdate {
        excluded = ids
        inventory = inventory.filter { !ids.contains($0.key) }
        schedule.setInventory(inventory.mapValues(\.kind), now: now())
        var update = SyncUpdate()
        for key in snapshots.keys where ids.contains(key.channelId) { update.merge(removing(key)) }
        return update
    }

    private func nextJob(now: Date) -> Job? {
        if inventoryDue <= now { return .inventory }
        return schedule.next(now: now).map(Job.conversation)
    }

    private var nextWake: Date? {
        [inventoryDue, schedule.nextDue].compactMap { $0 }.min()
    }

    private func run(_ job: Job, now: Date) async throws -> SyncUpdate {
        switch job {
        case .inventory: return try await takeInventory(now: now)
        case .conversation(let id): return try await check(id, now: now)
        }
    }

    // MARK: Inventory and conversations (spec §6.3 steps 1, 2 and 6)

    private func takeInventory(now: Date) async throws -> SyncUpdate {
        let all = try await slack.allConversations().filter { !excluded.contains($0.id) && $0.isArchived != true }
        inventory = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        schedule.setInventory(inventory.mapValues(\.kind), now: now)
        inventoryDue = now.addingTimeInterval(config.inventoryInterval)
        var update = SyncUpdate()
        for key in snapshots.keys where inventory[key.channelId] == nil { update.merge(removing(key)) }   // left or archived
        return update
    }

    private func check(_ id: String, now: Date) async throws -> SyncUpdate {
        guard let conversation = inventory[id] else { return SyncUpdate() }
        let key = ItemKey(teamId: workspace.teamId, channelId: id)
        let info = try await slack.conversationsInfo(id)
        let lastRead = SlackTS.isZero(info.lastRead) ? nil : info.lastRead
        if let lastRead, let hidden = readThrough[id], !SlackTS.isAfter(hidden, lastRead) { readThrough[id] = nil }

        // A DM that was never opened has last_read 0, which history refuses as `oldest`: Slack's own count says how many are unread.
        let neverOpenedDM = conversation.kind == .im && lastRead == nil
        var page: SlackHistory?
        if !neverOpenedDM || (info.unreadCountDisplay ?? 0) > 0 {
            let horizon = SlackTS.ts(now.addingTimeInterval(-config.unreadHorizon))
            let limit = neverOpenedDM ? min(info.unreadCountDisplay ?? 0, config.historyLimit) : config.historyLimit
            page = try await slack.conversationsHistory(id, oldest: SlackTS.latest(lastRead, horizon), latest: nil, inclusive: false, limit: limit)
        }
        let fetched = page?.messages ?? []
        let line = SlackTS.latest(lastRead, readThrough[id])
        let unread = fetched
            .filter { message in isShown(message) && message.user != workspace.userId && line.map { SlackTS.isAfter(message.ts, $0) } ?? true }
            .sorted(by: oldestFirst)
        let activity = SlackTS.latest(lastRead, fetched.first?.ts).map(SlackTS.date) ?? .distantPast
        schedule.checked(id, now: now, lastActivity: activity, hasUnread: !unread.isEmpty)

        guard let first = unread.first, let newest = unread.last else { return removing(key) }
        if let existing = snapshots[key], existing.newestTs == newest.ts, existing.unread.count == unread.count { return SyncUpdate() }
        let context = try await slack.conversationsHistory(id, oldest: nil, latest: first.ts, inclusive: false, limit: config.contextCount)
            .messages.filter(isShown).sorted(by: oldestFirst)
        let built = await snapshot(key, kind: kind(of: conversation), conversation: conversation,
                                   unread: unread, context: context, moreUnread: page?.hasMore ?? false)
        return isWanted(key, newest: built.newestTs) ? upserting(built) : removing(key)
    }

    /// After a check's awaits: the user may have excluded the channel or marked it read meanwhile.
    private func isWanted(_ key: ItemKey, newest: String) -> Bool {
        guard inventory[key.channelId] != nil, !excluded.contains(key.channelId) else { return false }
        return readThrough[key.channelId].map { SlackTS.isAfter(newest, $0) } ?? true
    }

    private func snapshot(_ key: ItemKey, kind: SnapshotKind, conversation: SlackConversation?, unread: [SlackMessage],
                          context: [SlackMessage], moreUnread: Bool) async -> ConversationSnapshot {
        var ids = Set(conversation?.user.map { [$0] } ?? [])
        for message in unread + context { ids.formUnion(MessageNormalizer.userIds(in: message)) }
        let normalizer = MessageNormalizer(names: await names.names(for: ids))
        func convert(_ m: SlackMessage) -> SnapshotMessage {
            SnapshotMessage(ts: m.ts, authorId: m.user, author: normalizer.author(of: m), text: normalizer.text(of: m),
                            mentionsMe: MessageNormalizer.mentions(workspace.userId, in: m))
        }
        let title = conversation.map { ConversationTitle.make($0, names: normalizer.names, myHandle: workspace.userName) } ?? key.channelId
        return ConversationSnapshot(key: key, kind: kind, title: title, unread: unread.map(convert), context: context.map(convert), moreUnread: moreUnread)
    }

    // MARK: Errors (spec §6.3 step 7)

    private func handle(_ error: Error, job: Job, now: Date) -> SyncUpdate {
        switch error {
        case SlackError.api(let code) where Self.revokedErrors.contains(code):
            return stop(.tokenRevoked)
        case SlackError.refreshFailed:
            return stop(.reauthorize)
        case SlackError.api("missing_scope"):
            status.missingScope = true
            postpone(job, until: now.addingTimeInterval(config.inventoryInterval))
        case SlackError.api(let code) where Self.goneErrors.contains(code):
            return forget(job)
        case SlackError.rateLimited(let retryAfter):
            postpone(job, until: now.addingTimeInterval(retryAfter))
        case SlackError.http(let status) where status >= 500:
            goOffline(now: now)
        case is URLError:
            goOffline(now: now)
        default:
            postpone(job, until: now.addingTimeInterval(60))   // unexpected: try again later rather than spin
        }
        return SyncUpdate()
    }

    /// 15 s, 30 s, 1 min, 2 min, 4 min, then every 5 min.
    private func goOffline(now: Date) {
        failures += 1
        let delay = min(15 * pow(2, Double(failures - 1)), config.maxBackoff)
        status.problem = .offline(retryAt: now.addingTimeInterval(delay))
    }

    private func stop(_ problem: SyncProblem) -> SyncUpdate {
        status.problem = problem
        var update = SyncUpdate()
        for key in snapshots.keys { update.merge(removing(key)) }
        return update
    }

    private func postpone(_ job: Job, until: Date) {
        switch job {
        case .inventory: inventoryDue = until
        case .conversation(let id): schedule.postpone(id, until: until)
        }
    }

    private func forget(_ job: Job) -> SyncUpdate {
        switch job {
        case .inventory:
            inventoryDue = now().addingTimeInterval(config.inventoryInterval)
            return SyncUpdate()
        case .conversation(let id):
            inventory.removeValue(forKey: id)
            schedule.setInventory(inventory.mapValues(\.kind), now: now())
            var update = SyncUpdate()
            for key in snapshots.keys where key.channelId == id { update.merge(removing(key)) }
            return update
        }
    }

    // MARK: Helpers

    private func upserting(_ snapshot: ConversationSnapshot) -> SyncUpdate {
        snapshots[snapshot.key] = snapshot
        var update = SyncUpdate()
        update.upsert(snapshot)
        return update
    }

    private func removing(_ key: ItemKey) -> SyncUpdate {
        var update = SyncUpdate()
        if snapshots.removeValue(forKey: key) != nil { update.remove(key) }
        return update
    }

    private func isShown(_ message: SlackMessage) -> Bool { Self.shownSubtypes.contains(message.subtype) }

    private func oldestFirst(_ a: SlackMessage, _ b: SlackMessage) -> Bool { SlackTS.isAfter(b.ts, a.ts) }

    private func kind(of conversation: SlackConversation) -> SnapshotKind {
        switch conversation.kind {
        case .im: .dm
        case .mpim: .groupDM
        case .privateChannel, .publicChannel: .channel
        }
    }
}
