import Foundation

/// A conversation's summary for one version of it (its newest message).
public struct TriageResult: Sendable, Equatable {
    public let key: ItemKey
    public let newestTs: String
    public let items: [TriageItem]   // one or two

    public init(key: ItemKey, newestTs: String, items: [TriageItem]) {
        self.key = key
        self.newestTs = newestTs
        self.items = items
    }
}

/// Why summaries are on hold. The panel header says so (spec §4.3, §9).
public enum TriagePause: Sendable, Equatable {
    case byUser                     // "Summaries paused"
    case signedOut                  // "Summaries paused: sign in again"
    case notEligible                // the ChatGPT plan can't be used
    case usageLimit(until: Date)    // "Summaries paused: ChatGPT usage limit, back at 15:40"
    case budget(until: Date)        // Splark's own limit of 30 requests an hour
}

public enum TriageState: Sendable, Equatable {
    case idle
    case summarising(Int)           // "Summarising 3 conversations"
    case paused(TriagePause)
}

/// Turns changed snapshots into summaries (spec §7.3): waits for a quiet moment, batches, asks the AI,
/// checks the answer, caches it, and keeps within budget. Anything it can't summarise gets the heuristic.
public actor Triage {
    public struct Config: Sendable {
        public var quiet: TimeInterval = 20          // after the last change
        public var maxWait: TimeInterval = 60        // after the first change
        public var batchSize = 15
        public var batchTokens = 12_000
        public var requestsPerHour = 30
        public var retryAfterFailure: TimeInterval = 60      // doubling on each failure in a row
        public var maxRetryDelay: TimeInterval = 1800
        public init() {}
    }

    private let llm: LLMClient?
    private let config: Config
    private let now: @Sendable () -> Date
    private var readers: [String: TriageReader] = [:]
    private var snapshots: [ItemKey: ConversationSnapshot] = [:]
    private var cache: [ItemKey: TriageResult] = [:]   // memory only: no message content reaches the disk
    private var dirty: Set<ItemKey> = []
    private var firstDirty: Date?
    private var lastDirty: Date?
    private var requestTimes: [Date] = []
    private var userPaused = false
    private var accountPause: TriagePause?           // signedOut or notEligible, until `resume()`
    private var usageLimitedUntil: Date?
    private var retryAt: Date?
    private var failures = 0
    private var inFlight = 0

    public init(llm: LLMClient?, config: Config = Config(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.llm = llm
        self.config = config
        self.now = now
    }

    public var state: TriageState {
        if inFlight > 0 { return .summarising(inFlight) }
        return pause.map(TriageState.paused) ?? .idle
    }

    /// Conversations waiting for a summary.
    public var waitingCount: Int { dirty.count }

    public func setReaders(_ readers: [String: TriageReader]) { self.readers = readers }

    /// Settings → Pause summaries.
    public func setPaused(_ paused: Bool) { userPaused = paused }

    /// After signing in again.
    public func resume() {
        accountPause = nil
        retryAt = nil
        failures = 0
    }

    /// Conversations whose newest message changed become due; removed ones are forgotten.
    public func update(_ update: SyncUpdate) {
        for key in update.removed {
            snapshots[key] = nil
            cache[key] = nil
            dirty.remove(key)
        }
        if dirty.isEmpty { firstDirty = nil; lastDirty = nil }
        for snapshot in update.upserted.values {
            snapshots[snapshot.key] = snapshot
            guard cache[snapshot.key]?.newestTs != snapshot.newestTs else { continue }
            dirty.insert(snapshot.key)
            firstDirty = firstDirty ?? now()
            lastDirty = now()
        }
    }

    /// When `flushIfDue` will next send a batch; nil when nothing is waiting or summaries are on hold.
    public var nextFlush: Date? {
        guard !dirty.isEmpty, let firstDirty, let lastDirty, llm != nil, !userPaused, accountPause == nil else { return nil }
        let due = [min(lastDirty.addingTimeInterval(config.quiet), firstDirty.addingTimeInterval(config.maxWait)),
                   usageLimitedUntil, budgetResumes, retryAt].compactMap { $0 }.max()!
        return max(due, now())
    }

    /// Sends one batch if one is due, and returns its summaries.
    public func flushIfDue() async -> [TriageResult] {
        guard let due = nextFlush, now() >= due, let llm else { return [] }
        let batch = nextBatch()
        dirty.subtract(batch.map(\.key))
        inFlight = batch.count
        defer { inFlight = 0 }
        let (input, ids) = TriagePrompt.input(for: batch, readers: readers, now: now())
        let request = LLMRequest(instructions: TriagePrompt.instructions, input: input, schemaName: TriagePrompt.schemaName,
                                 schemaJSON: TriagePrompt.schemaJSON)
        let byKey = Dictionary(uniqueKeysWithValues: batch.map { ($0.key, $0) })
        var parsed: [ItemKey: [TriageItem]]?
        do {
            for _ in 0..<2 where parsed == nil {   // an answer that isn't valid JSON is retried once
                requestTimes.append(now())
                let answer = try await llm.respond(request)
                parsed = try? TriagePrompt.parse(answer, ids: ids, snapshots: byKey)
            }
        } catch {
            requeue(batch)
            switch error {
            case LLMError.signedOut: accountPause = .signedOut
            case LLMError.notEligible: accountPause = .notEligible
            case LLMError.usageLimited(let until): usageLimitedUntil = until
            default:
                failures += 1
                retryAt = now().addingTimeInterval(min(config.retryAfterFailure * pow(2, Double(failures - 1)), config.maxRetryDelay))
            }
            return []
        }
        retryAt = nil
        failures = 0
        if dirty.isEmpty { firstDirty = nil; lastDirty = nil } else { firstDirty = .distantPast }   // the rest goes next
        return batch.compactMap { sent in
            guard snapshots[sent.key] != nil else { return nil }   // removed while we waited
            let result = TriageResult(key: sent.key, newestTs: sent.newestTs, items: parsed?[sent.key] ?? [TriagePrompt.heuristic(sent)])
            cache[sent.key] = result
            return result
        }
    }

    /// Direct conversations first, then the newest; up to 15 conversations or about 12k tokens.
    private func nextBatch() -> [ConversationSnapshot] {
        let waiting = dirty.compactMap { snapshots[$0] }.sorted { a, b in
            a.isDirect != b.isDirect ? a.isDirect : SlackTS.isAfter(a.newestTs, b.newestTs)
        }
        var batch: [ConversationSnapshot] = []
        var tokens = 0
        for snapshot in waiting {
            let cost = TriagePrompt.estimatedTokens(snapshot)
            if !batch.isEmpty, batch.count == config.batchSize || tokens + cost > config.batchTokens { break }
            batch.append(snapshot)
            tokens += cost
        }
        return batch
    }

    private func requeue(_ batch: [ConversationSnapshot]) {
        for snapshot in batch where snapshots[snapshot.key] != nil { dirty.insert(snapshot.key) }
        guard !dirty.isEmpty else { return }
        // A removal during the request may have reset these; without them nothing would ever be retried.
        firstDirty = firstDirty ?? .distantPast
        lastDirty = lastDirty ?? .distantPast
    }

    private var pause: TriagePause? {
        if userPaused { return .byUser }
        if llm == nil { return .signedOut }
        if let accountPause { return accountPause }
        if let until = usageLimitedUntil, now() < until { return .usageLimit(until: until) }
        return budgetResumes.map(TriagePause.budget)
    }

    /// When the oldest of the last hour's requests leaves the window, if the hour's budget is spent.
    private var budgetResumes: Date? {
        requestTimes.removeAll { now().timeIntervalSince($0) >= 3600 }
        guard requestTimes.count >= config.requestsPerHour else { return nil }
        return requestTimes.min()?.addingTimeInterval(3600)
    }
}
