import Foundation
import os

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
    /// Why syncing stopped, for Settings and the system log: "Slack said invalid_refresh_token". Never message text.
    public var reason: String?

    public init(problem: SyncProblem? = nil, missingScope: Bool = false, progress: SyncSchedule.Progress = .init(checked: 0, total: 0),
                lastSuccess: Date? = nil, reason: String? = nil) {
        self.problem = problem
        self.reason = reason
        self.missingScope = missingScope
        self.progress = progress
        self.lastSuccess = lastSuccess
    }
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

/// What a workspace's sync remembers across launches: IDs and timestamps only (spec §8).
public struct SyncMemory: Codable, Sendable, Equatable {
    public var threads = ThreadTracker()
    public var sweptThrough: String?   // the newest search hit already handled
    public init() {}
}

/// Finds one workspace's unread conversations (spec §6.3). `step()` does the most overdue piece of work
/// and returns; the app calls it in a loop and sleeps until `nextWake` when nothing is due.
public actor SyncEngine {
    public struct Config: Sendable {
        public var inventoryInterval: TimeInterval = 1800
        public var sweepInterval: TimeInterval = 120
        public var firstSweepLookback: TimeInterval = 86400
        public var sweepOverlap: TimeInterval = 600            // search indexes late: look again at the last 10 minutes
        public var threadExpiry: TimeInterval = 86400         // thread items clear a day after their newest reply
        public var unreadHorizon: TimeInterval = 14 * 86400   // older unread messages are left out
        public var historyLimit = 40
        public var repliesPageSize = 200                       // up to 5 pages: a thread's newest 1,000 replies
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
    private var everything: [String: SlackConversation] = [:]   // every conversation the user is in, excluded or not
    private var inventory: [String: SlackConversation] = [:]    // the ones Splark syncs
    private var inventoryDue = Date.distantPast
    private var readThrough: [String: String] = [:]   // marked read in Splark; Slack's last_read may lag behind
    private var fingerprints: [ItemKey: [String]] = [:]   // the unread messages as last sent, so an edit counts as a change
    private var sweepDue = Date.distantPast
    private var inventoryLoaded = false
    private var sweptHits: [String: Date] = [:]        // "channel/ts" of search hits already handled, within the overlap
    private var badge: SlackBadge?
    private var badgeSeenLit = false   // a clear badge counts only after a lit one has been seen since Slack started
    private var failures = 0
    public private(set) var memory: SyncMemory
    public private(set) var snapshots: [ItemKey: ConversationSnapshot] = [:]
    public private(set) var status = SyncStatus()

    public init(workspace: Workspace, slack: SlackAPI, names: UserDirectory, memory: SyncMemory = SyncMemory(),
                excluded: Set<String> = [], config: Config = Config(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.workspace = workspace
        self.memory = memory
        self.slack = slack
        self.names = names
        self.excluded = excluded
        self.config = config
        self.now = now
        self.schedule = SyncSchedule(intervals: config.schedule)
    }

    private enum Job { case inventory, sweep, conversation(String), thread(ThreadWatch) }

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
    /// Threads have no read marker in Slack, so their line moves instead.
    /// Anything newer than `ts` that arrived meanwhile stays.
    public func markedRead(_ key: ItemKey, through ts: String) -> SyncUpdate {
        if let threadTs = key.threadTs {
            memory.threads.clear(channelId: key.channelId, threadTs: threadTs, through: ts)
        } else {
            readThrough[key.channelId] = SlackTS.latest(readThrough[key.channelId], ts)
        }
        guard let snapshot = snapshots[key], SlackTS.isAfter(snapshot.newestTs, ts) else { return removing(key) }
        let read = snapshot.unread.filter { !SlackTS.isAfter($0.ts, ts) }
        return upserting(ConversationSnapshot(key: key, kind: snapshot.kind, title: snapshot.title,
                                              unread: snapshot.unread.filter { SlackTS.isAfter($0.ts, ts) },
                                              context: Array((snapshot.context + read).suffix(config.contextCount)), moreUnread: false))
    }

    /// Splark posted a reply. In a thread, everything before it is read, and later replies are watched.
    public func didReply(channelId: String, threadTs: String?, ts: String) {
        guard let threadTs else { return }
        memory.threads.userReplied(channelId: channelId, threadTs: threadTs, ts: ts, now: now())
    }

    /// Slack's Dock badge changed (spec §6.3 steps 3 and 5): check DMs, busy conversations and threads now.
    /// A clear badge means the user has caught up in Slack, threads included, but only once a lit badge has been seen.
    public func badgeChanged(_ badge: SlackBadge?) -> SyncUpdate {
        let previous = self.badge
        self.badge = badge
        switch badge {
        case .dot?, .count?: badgeSeenLit = true
        case nil: badgeSeenLit = false   // Slack quit: start over
        case .clear?: break
        }
        guard badge != previous, badge != nil else { return SyncUpdate() }
        schedule.wakeDirect(now: now())
        memory.threads.wakeAll()
        guard badge == .clear, badgeSeenLit else { return SyncUpdate() }
        memory.threads.clearAll(through: SlackTS.ts(now()))   // threads without an item yet too
        var update = SyncUpdate()
        for key in snapshots.keys where key.threadTs != nil { update.merge(removing(key)) }
        return update
    }

    /// "Refresh now": DMs, busy conversations, threads and the mention sweep, straight away.
    public func refreshNow() {
        let now = now()
        schedule.wakeDirect(now: now)
        memory.threads.wakeAll()
        sweepDue = .distantPast
        if case .offline? = status.problem { status.problem = .offline(retryAt: now) }
    }

    /// Every conversation the user is in, excluded ones included (for the exclusions picker).
    public var conversations: [SlackConversation] { everything.values.sorted { $0.id < $1.id } }

    /// Takes effect at once both ways: a channel no longer excluded is due straight away.
    public func setExcluded(_ ids: Set<String>) -> SyncUpdate {
        excluded = ids
        inventory = everything.filter { !ids.contains($0.key) }
        schedule.setInventory(inventory.mapValues(\.kind), now: now())
        var update = SyncUpdate()
        for key in snapshots.keys where ids.contains(key.channelId) { update.merge(removing(key)) }
        return update
    }

    /// The inventory first; then whatever has waited longest: a conversation, a thread or the sweep.
    private func nextJob(now: Date) -> Job? {
        if inventoryDue <= now { return .inventory }
        var candidates: [(due: Date, rank: Int, job: Job)] = []
        if let id = schedule.next(now: now), let due = schedule.entries[id]?.due { candidates.append((due, 0, .conversation(id))) }
        if let watch = memory.threads.due(now: now).first { candidates.append((watch.due, 1, .thread(watch))) }
        if inventoryLoaded, sweepDue <= now { candidates.append((sweepDue, 2, .sweep)) }
        return candidates.min { ($0.due, $0.rank) < ($1.due, $1.rank) }?.job
    }

    private var nextWake: Date? {
        [inventoryDue, sweepDue, schedule.nextDue, memory.threads.nextDue].compactMap { $0 }.min()
    }

    private func run(_ job: Job, now: Date) async throws -> SyncUpdate {
        switch job {
        case .inventory: return try await takeInventory(now: now)
        case .sweep: return try await sweep(now: now)
        case .conversation(let id): return try await check(id, now: now)
        case .thread(let watch): return try await check(watch, now: now)
        }
    }

    // MARK: Inventory and conversations (spec §6.3 steps 1, 2 and 6)

    private func takeInventory(now: Date) async throws -> SyncUpdate {
        let all = try await slack.allConversations().filter { $0.isArchived != true }
        everything = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        inventory = everything.filter { !excluded.contains($0.key) }
        schedule.setInventory(inventory.mapValues(\.kind), now: now)
        inventoryDue = now.addingTimeInterval(config.inventoryInterval)
        inventoryLoaded = true
        memory.threads.prune(now: now)
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
        watchThreads(in: fetched, channelId: id, now: now)
        let line = SlackTS.latest(lastRead, readThrough[id])
        let unread = fetched
            .filter { message in isShown(message) && message.user != workspace.userId && line.map { SlackTS.isAfter(message.ts, $0) } ?? true }
            .sorted(by: oldestFirst)
        let activity = SlackTS.latest(lastRead, fetched.first?.ts).map(SlackTS.date) ?? .distantPast
        schedule.checked(id, now: now, lastActivity: activity, hasUnread: !unread.isEmpty)

        guard let first = unread.first else { return removing(key) }
        if snapshots[key] != nil, fingerprints[key] == fingerprint(unread) { return SyncUpdate() }
        let context = try await slack.conversationsHistory(id, oldest: nil, latest: first.ts, inclusive: false, limit: config.contextCount)
            .messages.filter(isShown).sorted(by: oldestFirst)
        watchThreads(in: context, channelId: id, now: now)
        // A never-opened DM asked for exactly its unread count, so Slack's has_more only means older, read history.
        let moreUnread = neverOpenedDM ? (info.unreadCountDisplay ?? 0) > config.historyLimit : page?.hasMore ?? false
        let built = await snapshot(key, kind: kind(of: conversation), conversation: conversation,
                                   unread: unread, context: context, moreUnread: moreUnread)
        guard isWanted(key, newest: built.newestTs) else { return removing(key) }
        fingerprints[key] = fingerprint(unread)
        return upserting(built)
    }

    /// After a check's awaits: the user may have excluded the channel, marked it read or cleared its thread meanwhile.
    private func isWanted(_ key: ItemKey, newest: String) -> Bool {
        guard inventory[key.channelId] != nil, !excluded.contains(key.channelId) else { return false }
        if let threadTs = key.threadTs {
            guard let line = memory.threads.watch(channelId: key.channelId, threadTs: threadTs)?.seenThrough else { return false }
            return SlackTS.isAfter(newest, line)
        }
        return readThrough[key.channelId].map { SlackTS.isAfter(newest, $0) } ?? true
    }

    // MARK: Threads and the mention sweep (spec §6.3 steps 4 and 5)

    /// Threads the user started or replied to, seen in history. Replies from the last day count until
    /// the first check finds where the user's own last reply is.
    private func watchThreads(in messages: [SlackMessage], channelId: String, now: Date) {
        let me = workspace.userId
        for message in messages where (message.replyCount ?? 0) > 0 && (message.user == me || message.replyUsers?.contains(me) == true) {
            let known = memory.threads.watch(channelId: channelId, threadTs: message.ts) != nil
            let baseline = SlackTS.latest(message.ts, SlackTS.ts(now.addingTimeInterval(-config.threadExpiry))) ?? message.ts
            memory.threads.watch(channelId: channelId, threadTs: message.ts, seenThrough: baseline,
                                 activity: SlackTS.date(message.latestReply ?? message.ts), now: now)
            if known, let latest = message.latestReply, memory.threads.isUnseen(latest, channelId: channelId, threadTs: message.ts) {
                memory.threads.wake(channelId: channelId, threadTs: message.ts)
            }
        }
    }

    private func check(_ watch: ThreadWatch, now: Date) async throws -> SyncUpdate {
        let key = ItemKey(teamId: workspace.teamId, channelId: watch.channelId, threadTs: watch.threadTs)
        guard !excluded.contains(watch.channelId) else {
            memory.threads.remove(channelId: watch.channelId, threadTs: watch.threadTs)
            return removing(key)
        }
        let me = workspace.userId
        // Replies come oldest first: page until the newest, so a long thread doesn't freeze on its first 40.
        var fetched: [SlackMessage] = []
        var parent: SlackMessage?
        var hasMore = false
        var oldest = watch.seenThrough
        for _ in 0..<5 {
            let page = try await slack.conversationsReplies(watch.channelId, ts: watch.threadTs, oldest: oldest, limit: config.repliesPageSize)
            parent = parent ?? page.messages.first { $0.ts == watch.threadTs }
            let fresh = page.messages.filter { $0.ts != watch.threadTs && SlackTS.isAfter($0.ts, oldest) }
            fetched += fresh
            hasMore = page.hasMore ?? false
            guard hasMore, let last = SlackTS.latest(fresh.map(\.ts)) else { break }
            oldest = last
        }
        let replies = fetched.filter(isShown).sorted(by: oldestFirst)
        if let mine = replies.last(where: { $0.user == me }) {
            memory.threads.userReplied(channelId: watch.channelId, threadTs: watch.threadTs, ts: mine.ts, now: now)
        }
        let line = memory.threads.watch(channelId: watch.channelId, threadTs: watch.threadTs)?.seenThrough ?? watch.seenThrough
        let unread = replies.filter { $0.user != me && SlackTS.isAfter($0.ts, line) }
        memory.threads.checked(channelId: watch.channelId, threadTs: watch.threadTs, newestReply: SlackTS.latest(fetched.map(\.ts)), now: now)

        guard let first = unread.first, let newest = unread.last else { return removing(key) }
        // Slack has no thread read state, and its badge can stay lit for days: a thread item goes a day after its newest reply.
        if now.timeIntervalSince(SlackTS.date(newest.ts)) > config.threadExpiry {
            memory.threads.clear(channelId: watch.channelId, threadTs: watch.threadTs, through: newest.ts)
            return removing(key)
        }
        if snapshots[key] != nil, fingerprints[key] == fingerprint(unread) { return SyncUpdate() }
        if parent == nil {
            parent = try await slack.conversationsReplies(watch.channelId, ts: watch.threadTs, oldest: nil, limit: 1).messages.first { $0.ts == watch.threadTs }
        }
        let context = [parent].compactMap { $0 } + replies.filter { SlackTS.isAfter(first.ts, $0.ts) }.suffix(2)
        let built = await snapshot(key, kind: .thread, conversation: inventory[watch.channelId], unread: unread, context: context, moreUnread: hasMore)
        guard isWanted(key, newest: built.newestTs) else { return removing(key) }
        fingerprints[key] = fingerprint(unread)
        return upserting(built)
    }

    /// `search.messages` for mentions of the user, and for the user's own recent replies. Search indexes late, so each
    /// sweep looks again at the 10 minutes before the newest mention handled, skipping hits it already handled.
    /// Thread hits start watches; a top-level mention makes its conversation due now.
    private func sweep(now: Date) async throws -> SyncUpdate {
        let me = workspace.userId
        // Never further back than the first sweep's look-back, however old the last mention handled.
        let since = SlackTS.latest(memory.sweptThrough.map { SlackTS.ts(SlackTS.date($0).addingTimeInterval(-config.sweepOverlap)) },
                                   SlackTS.ts(now.addingTimeInterval(-config.firstSweepLookback)))!
        let mentions = try await slack.searchMessages("<@\(me)>", count: 20).messages.matches
        // Best effort: finds threads the user replied to in Slack itself. Never let it stop the mention sweep.
        let replies = (try? await slack.searchMessages("from:<@\(me)>", count: 20))?.messages.matches ?? []
        sweptHits = sweptHits.filter { now.timeIntervalSince($0.value) < 2 * config.sweepOverlap }
        func fresh(_ hit: SlackSearchResult.Match) -> Bool {
            SlackTS.isAfter(hit.ts, since) && inventory[hit.channel.id] != nil && sweptHits.updateValue(now, forKey: "\(hit.channel.id)/\(hit.ts)") == nil
        }
        for hit in mentions where fresh(hit) {
            if let threadTs = hit.threadTs, threadTs != hit.ts {
                let known = memory.threads.watch(channelId: hit.channel.id, threadTs: threadTs) != nil
                memory.threads.watch(channelId: hit.channel.id, threadTs: threadTs, seenThrough: SlackTS.justBefore(hit.ts),
                                     activity: SlackTS.date(hit.ts), now: now)
                if known, memory.threads.isUnseen(hit.ts, channelId: hit.channel.id, threadTs: threadTs) {
                    memory.threads.wake(channelId: hit.channel.id, threadTs: threadTs)
                }
            } else {
                schedule.wake(hit.channel.id)
            }
        }
        for hit in replies where fresh(hit) {
            guard let threadTs = hit.threadTs, threadTs != hit.ts else { continue }
            memory.threads.userReplied(channelId: hit.channel.id, threadTs: threadTs, ts: hit.ts, now: now)
        }
        // Only mentions inside the window move the mark; the user's own messages don't.
        memory.sweptThrough = SlackTS.latest([memory.sweptThrough] + mentions.map(\.ts).filter { SlackTS.isAfter($0, since) })
        sweepDue = now.addingTimeInterval(config.sweepInterval)
        return SyncUpdate()
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
            return stop(.tokenRevoked, reason: "Slack said \(code)")
        case SlackError.refreshFailed(let code):
            return stop(.reauthorize, reason: "Slack said \(code)")
        case SlackError.api("missing_scope"):
            status.missingScope = true
            if case .conversation(let id) = job {   // counted as checked, so "Catching up…" can finish
                schedule.checked(id, now: now, lastActivity: nil, hasUnread: false)
            }
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

    private func stop(_ problem: SyncProblem, reason: String) -> SyncUpdate {
        status.problem = problem
        status.reason = reason
        Logger.sync.error("\(self.workspace.name, privacy: .public) stopped syncing: \(reason, privacy: .public)")
        var update = SyncUpdate()
        for key in snapshots.keys { update.merge(removing(key)) }
        return update
    }

    private func postpone(_ job: Job, until: Date) {
        switch job {
        case .inventory: inventoryDue = until
        case .sweep: sweepDue = until
        case .conversation(let id): schedule.postpone(id, until: until)
        case .thread(let watch): memory.threads.postpone(channelId: watch.channelId, threadTs: watch.threadTs, until: until)
        }
    }

    private func forget(_ job: Job) -> SyncUpdate {
        switch job {
        case .inventory:
            inventoryDue = now().addingTimeInterval(config.inventoryInterval)
            return SyncUpdate()
        case .sweep:
            sweepDue = now().addingTimeInterval(config.inventoryInterval)
            return SyncUpdate()
        case .thread(let watch):
            memory.threads.remove(channelId: watch.channelId, threadTs: watch.threadTs)
            return removing(ItemKey(teamId: workspace.teamId, channelId: watch.channelId, threadTs: watch.threadTs))
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

    private func fingerprint(_ messages: [SlackMessage]) -> [String] {
        messages.map { "\($0.ts)|\($0.text ?? "")|\($0.files?.count ?? 0)" }
    }

    private func removing(_ key: ItemKey) -> SyncUpdate {
        fingerprints[key] = nil
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

extension Logger {
    /// Why a workspace stopped syncing, in the system log (`log show --predicate 'subsystem == "dev.splark.Splark"'`).
    /// Error codes and workspace names only, never message text or tokens.
    static let sync = Logger(subsystem: "dev.splark.Splark", category: "sync")
}
