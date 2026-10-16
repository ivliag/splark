import Foundation
import Testing
@testable import SplarkKit

@Suite struct TriageEvalTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Answers each conversation with the level `answer` picks from its newest message.
    func model(_ answer: @escaping @Sendable (String) -> TriageLevel) -> FakeLLM {
        FakeLLM { request in
            let json = try JSONSerialization.jsonObject(with: Data(request.input.utf8)) as? [String: Any]
            let items = (json?["conversations"] as? [[String: Any]] ?? []).map { conversation -> String in
                let newest = (conversation["messages"] as? [[String: Any]])?.last?["text"] as? String ?? ""
                return #"{"conversation_id":"\#(conversation["conversation_id"]!)","level":"\#(answer(newest).rawValue)","lead":"lead","rest":"","reason":"","anchor_ts":""}"#
            }
            return #"{"items":[\#(items.joined(separator: ","))]}"#
        }
    }

    @Test func theSetCoversEveryLevel() {
        let cases = TriageEval.cases(now: now)
        #expect(cases.count >= 20)
        #expect(Set(cases.map(\.name)).count == cases.count)
        for level in TriageLevel.allCases { #expect(cases.filter { $0.expected == level }.count >= 5) }
        #expect(Set(cases.map(\.snapshot.kind)) == [.dm, .groupDM, .channel, .thread])
    }

    @Test func aModelThatAgreesScoresFull() async throws {
        let expected = Dictionary(uniqueKeysWithValues: TriageEval.cases(now: now).map { ($0.snapshot.unread.last!.text, $0.expected) })
        let report = try await TriageEval.run(model { expected[$0]! }, now: now)
        #expect(report.accuracy == 1 && report.mismatches.isEmpty)
        #expect(report.outcomes.allSatisfy { $0.byAI })
    }

    @Test func mismatchesAreListed() async throws {
        let cases = TriageEval.cases(now: now)
        let report = try await TriageEval.run(model { _ in .fyi }, now: now)
        #expect(report.mismatches.count == cases.filter { $0.expected != .fyi }.count)
        #expect(abs(report.accuracy - Double(cases.filter { $0.expected == .fyi }.count) / Double(cases.count)) < 0.0001)
    }

    @Test func aFailingModelStopsTheRun() async {
        await #expect(throws: LLMError.signedOut) { try await TriageEval.run(FakeLLM { _ in throw LLMError.signedOut }, now: now) }
    }
}
