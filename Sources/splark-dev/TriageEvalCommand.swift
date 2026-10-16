import Foundation
import SplarkKit

/// Runs the triage evaluation set against your ChatGPT plan and prints the mismatches (spec §10). Not run in CI.
func triageEvalCommand() async throws {
    let llm = ChatGPTLLMClient(session: ChatGPTSession(store: store), chosenModel: option("--model"))
    let model = ChatGPTLLMClient.pickModel(available: try await llm.models(), chosen: option("--model")) ?? "?"
    print("Running \(TriageEval.cases(now: Date()).count) conversations through \(model)…")
    let started = Date()
    let report = try await TriageEval.run(llm)
    for outcome in report.outcomes {
        let mark = outcome.got == outcome.expected ? "✓" : "✗"
        print("\(mark) \(outcome.name.padding(toLength: 20, withPad: " ", startingAt: 0)) expected \(outcome.expected.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) got \(outcome.got.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0))\(outcome.byAI ? "" : " (heuristic)")  \(outcome.lead)")
    }
    print(String(format: "\n%d of %d right (%.0f%%) in %.1f s. The spec's bar is 80%%.", report.outcomes.count - report.mismatches.count,
                 report.outcomes.count, report.accuracy * 100, Date().timeIntervalSince(started)))
}
