import Foundation
import Testing
@testable import SplarkKit

/// An LLM that answers through a closure and records what it was asked.
final class FakeLLM: LLMClient, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [LLMRequest] = []
    private let answer: @Sendable (LLMRequest) throws -> String
    init(_ answer: @escaping @Sendable (LLMRequest) throws -> String) { self.answer = answer }
    var requests: [LLMRequest] { lock.withLock { log } }
    func respond(_ request: LLMRequest) async throws -> String {
        lock.withLock { log.append(request) }
        return try answer(request)
    }

    /// The conversation IDs in a request's input, in order.
    static func ids(_ request: LLMRequest) -> [String] {
        let json = try? JSONSerialization.jsonObject(with: Data(request.input.utf8)) as? [String: Any]
        return (json?["conversations"] as? [[String: Any]] ?? []).compactMap { $0["conversation_id"] as? String }
    }

    /// Answers every conversation in the request with `level`.
    static func everything(_ level: TriageLevel) -> FakeLLM {
        FakeLLM { request in
            let items = ids(request).map { #"{"conversation_id":"\#($0)","level":"\#(level.rawValue)","lead":"Lead \#($0)","rest":"rest","reason":"why","anchor_ts":""}"# }
            return #"{"items":[\#(items.joined(separator: ","))]}"#
        }
    }
}

func update(_ snapshots: [ConversationSnapshot], removed: [ItemKey] = []) -> SyncUpdate {
    var u = SyncUpdate()
    snapshots.forEach { u.upsert($0) }
    removed.forEach { u.remove($0) }
    return u
}

func channelSnapshot(_ id: String, newest: Int = -60, kind: SnapshotKind = .channel, text: String = "hello") -> ConversationSnapshot {
    snapshot(id, kind: kind, unread: [(ts(newest), "Leo", text, false)])
}

@Suite struct TriageTests {
    let clock = ManualClock()
    func triage(_ llm: LLMClient?, config: Triage.Config = Triage.Config()) -> Triage {
        Triage(llm: llm, config: config, now: { clock.now })
    }

    @Test func waitsForTwentyQuietSecondsButNoMoreThanAMinute() async {
        let llm = FakeLLM.everything(.question)
        let t = triage(llm)
        let start = clock.now
        await t.update(update([channelSnapshot("C1")]))
        #expect(await t.nextFlush == start.addingTimeInterval(20))
        for step in 1...5 {
            clock.advance(10)
            await t.update(update([channelSnapshot("C\(step + 1)")]))
        }
        #expect(await t.nextFlush == start.addingTimeInterval(60))   // still changing: the first change caps the wait
        #expect(await t.waitingCount == 6)
        clock.advance(5)
        #expect(await t.flushIfDue().isEmpty)                       // t+55: not yet
        clock.advance(5)
        #expect(await t.flushIfDue().count == 6)
        #expect(await t.nextFlush == nil)
    }

    @Test func batchesFifteenConversationsDirectOnesFirst() async {
        let llm = FakeLLM.everything(.fyi)
        let t = triage(llm)
        let channels = (1...17).map { channelSnapshot("C\($0)", newest: -$0) }
        let dms = (1...3).map { channelSnapshot("D\($0)", newest: -100 - $0, kind: .dm) }
        await t.update(update(channels + dms))
        clock.advance(20)
        let first = await t.flushIfDue()
        #expect(first.count == 15)
        #expect(Set(first.prefix(3).map(\.key.channelId)) == ["D1", "D2", "D3"])
        #expect(await t.nextFlush == clock.now)                     // the rest goes straight away
        #expect(await t.flushIfDue().count == 5)
    }

    @Test func batchesStayNearTwelveThousandTokens() async {
        let llm = FakeLLM.everything(.fyi)
        let t = triage(llm)
        let big = String(repeating: "word ", count: 190)   // ~950 characters a message
        let heavy = (1...3).map { i in
            snapshot("C\(i)", unread: (0..<20).map { (ts(-1000 + $0), "Leo", big, false) })   // ~5k tokens each
        }
        await t.update(update(heavy))
        clock.advance(20)
        #expect(await t.flushIfDue().count == 2)
        #expect(await t.flushIfDue().count == 1)
    }

    @Test func anUnchangedConversationIsNotSentAgain() async {
        let llm = FakeLLM.everything(.question)
        let t = triage(llm)
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        _ = await t.flushIfDue()
        await t.update(update([channelSnapshot("C1")]))
        #expect(await t.nextFlush == nil)
        await t.update(update([channelSnapshot("C1", newest: -1)]))
        #expect(await t.nextFlush != nil)
    }

    @Test func aConversationTheAnswerSkipsGetsTheHeuristic() async throws {
        let llm = FakeLLM { request in
            let first = FakeLLM.ids(request)[0]
            return #"{"items":[{"conversation_id":"\#(first)","level":"action","lead":"Do it","rest":"","reason":"","anchor_ts":""}]}"#
        }
        let t = triage(llm)
        await t.update(update([channelSnapshot("D1", kind: .dm), channelSnapshot("C1")]))
        clock.advance(20)
        let results = Dictionary(uniqueKeysWithValues: await t.flushIfDue().map { ($0.key.channelId, $0) })
        #expect(results["D1"]?.items.map(\.level) == [.action])
        #expect(results["C1"]?.items.map(\.byAI) == [false])
    }

    @Test func badOutputIsRetriedOnceThenEveryoneGetsTheHeuristic() async {
        let llm = FakeLLM { _ in "Sure! Here you go." }
        let t = triage(llm)
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        let results = await t.flushIfDue()
        #expect(llm.requests.count == 2)
        #expect(results.flatMap(\.items).map(\.byAI) == [false])
        #expect(await t.nextFlush == nil)   // not retried until the conversation changes
    }

    @Test func aUsageLimitPausesUntilItResets() async {
        let until = clock.now.addingTimeInterval(600)
        let limited = LockedBox(true)
        let llm = FakeLLM { request in
            if limited.value { throw LLMError.usageLimited(until: until) }
            return try FakeLLM.everything(.fyi).answerSync(request)
        }
        let t = triage(llm)
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        #expect(await t.flushIfDue().isEmpty)
        #expect(await t.state == .paused(.usageLimit(until: until)))
        #expect(await t.nextFlush == until)
        limited.value = false
        clock.advance(580)
        #expect(await t.flushIfDue().count == 1)
        #expect(await t.state == .idle)
    }

    /// After Reset another ChatGPT account may sign in: the old one's usage limit doesn't carry over.
    @Test func forgetAllForgetsAUsageLimit() async {
        let until = clock.now.addingTimeInterval(3600)
        let llm = FakeLLM { _ in throw LLMError.usageLimited(until: until) }
        let t = triage(llm)
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        _ = await t.flushIfDue()
        #expect(await t.state == .paused(.usageLimit(until: until)))
        await t.forgetAll()
        #expect(await t.state == .idle)
    }

    @Test func signedOutWaitsForSignIn() async {
        let llm = FakeLLM { _ in throw LLMError.signedOut }
        let t = triage(llm)
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        #expect(await t.flushIfDue().isEmpty)
        #expect(await t.state == .paused(.signedOut))
        #expect(await t.nextFlush == nil)
        await t.resume()
        #expect(await t.nextFlush == clock.now)
    }

    @Test func noSignedInAccountMeansNoRequests() async {
        let t = triage(nil)
        await t.update(update([channelSnapshot("C1")]))
        #expect(await t.state == .paused(.signedOut))
        #expect(await t.nextFlush == nil)
    }

    @Test func atMostThirtyRequestsAnHour() async {
        let llm = FakeLLM.everything(.fyi)
        let t = triage(llm)
        let start = clock.now
        for i in 1...31 {
            await t.update(update([channelSnapshot("C\(i)")]))
            clock.advance(20)
            _ = await t.flushIfDue()
        }
        #expect(llm.requests.count == 30)
        #expect(await t.state == .paused(.budget(until: start.addingTimeInterval(20 + 3600))))
        #expect(await t.nextFlush == start.addingTimeInterval(20 + 3600))
    }

    @Test func pausingStopsRequestsUntilResumed() async {
        let llm = FakeLLM.everything(.fyi)
        let t = triage(llm)
        await t.setPaused(true)
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        #expect(await t.flushIfDue().isEmpty && llm.requests.isEmpty)
        #expect(await t.state == .paused(.byUser))
        await t.setPaused(false)
        #expect(await t.flushIfDue().count == 1)
    }

    @Test func removedConversationsAreNotSent() async {
        let llm = FakeLLM.everything(.fyi)
        let t = triage(llm)
        await t.update(update([channelSnapshot("C1"), channelSnapshot("C2")]))
        await t.update(update([], removed: [ItemKey(teamId: "T1", channelId: "C1")]))
        clock.advance(20)
        #expect(await t.flushIfDue().map(\.key.channelId) == ["C2"])
    }

    @Test func failedRequestsAreRetriedLessAndLessOften() async {
        let llm = FakeLLM { _ in throw LLMError.unavailable("offline") }
        let t = triage(llm)
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        var delays: [TimeInterval] = []
        for _ in 0..<7 {
            #expect(await t.flushIfDue().isEmpty)
            let next = await t.nextFlush!
            delays.append(next.timeIntervalSince(clock.now))
            clock.advance(next.timeIntervalSince(clock.now))
        }
        #expect(delays == [60, 120, 240, 480, 960, 1800, 1800])
    }

    @Test func aFailedRequestIsRetriedEvenIfSomethingWasRemovedMeanwhile() async {
        let box = LockedBox<Triage?>(nil)
        let llm = HookLLM {
            // While the request is out, the user reads C2 in Slack, then the network drops.
            if let t = box.value { await t.update(update([], removed: [ItemKey(teamId: "T1", channelId: "C2")])) }
            throw LLMError.unavailable("offline")
        }
        let t = triage(llm)
        box.value = t
        await t.update(update([channelSnapshot("C1"), channelSnapshot("C2")]))
        clock.advance(20)
        #expect(await t.flushIfDue().isEmpty)
        #expect(await t.waitingCount == 1)
        #expect(await t.nextFlush == clock.now.addingTimeInterval(60))
    }

    @Test func aChangeAfterEverythingWasRemovedWaitsTheFullTwentySeconds() async {
        let t = triage(FakeLLM.everything(.fyi))
        await t.update(update([channelSnapshot("C1")]))
        await t.update(update([], removed: [ItemKey(teamId: "T1", channelId: "C1")]))
        clock.advance(100)
        await t.update(update([channelSnapshot("C2")]))
        #expect(await t.nextFlush == clock.now.addingTimeInterval(20))
    }

    @Test func requestsCarryTheInstructionsAndSchema() async {
        let llm = FakeLLM.everything(.fyi)
        let t = triage(llm)
        await t.setReaders(["T1": TriageReader(name: "Ivan", userId: "U1", workspace: "Lumen")])
        await t.update(update([channelSnapshot("C1")]))
        clock.advance(20)
        _ = await t.flushIfDue()
        let request = llm.requests[0]
        #expect(request.instructions == TriagePrompt.instructions && request.schemaJSON == TriagePrompt.schemaJSON)
        #expect(request.input.contains(#""name":"Ivan""#))
    }
}

/// An LLM that runs `hook` (which may call back into triage) and then whatever it throws or returns.
final class HookLLM: LLMClient, @unchecked Sendable {
    let hook: @Sendable () async throws -> String
    init(_ hook: @escaping @Sendable () async throws -> String) { self.hook = hook }
    func respond(_ request: LLMRequest) async throws -> String { try await hook() }
}

extension FakeLLM {
    func answerSync(_ request: LLMRequest) throws -> String { try answer(request) }
}

@Suite struct TriageSignOutTests {
    @Test func signingOutPausesAtOnce() async {
        let t = Triage(llm: FakeLLM.everything(.fyi), now: { Date(timeIntervalSince1970: 0) })
        await t.signedOut()
        #expect(await t.state == .paused(.signedOut))
        await t.resume()
        #expect(await t.state == .idle)
    }

    @Test func forgetAllDropsEverythingWaiting() async {
        let t = Triage(llm: FakeLLM.everything(.fyi), now: { Date(timeIntervalSince1970: 0) })
        await t.update(update([channelSnapshot("C1")]))
        await t.forgetAll()
        #expect(await t.waitingCount == 0)
        #expect(await t.nextFlush == nil)
    }
}
