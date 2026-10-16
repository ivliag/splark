import Foundation
import SplarkKit

/// Runs the whole engine against your connected workspace and ChatGPT, printing the inbox when it changes.
/// `--no-text` leaves out the summaries (levels, sources and counts only).
@MainActor func inboxCommand() async throws {
    let minutes = Double(option("--minutes") ?? "3") ?? 3
    let showText = !args.contains("--no-text")
    let (slack, credentials) = try await devSlack()
    let me = try await slack.authTest()
    let workspace = Workspace(teamId: me.teamId, name: me.team ?? me.teamId, userId: me.userId, userName: me.user, url: me.url, redirectPort: nil, appId: nil)
    let stateURL = StateStore.defaultURL.deletingLastPathComponent().appendingPathComponent("dev-state.json")
    let splark = SplarkEngine(environment: .live(keychainService: "dev.splark.dev", stateURL: stateURL))
    if !splark.workspaces.contains(where: { $0.teamId == workspace.teamId }) {
        try await splark.connect(SlackConnection(workspace: workspace, credentials: credentials))
    }
    splark.start()
    print("Running for \(Int(minutes)) min against \(workspace.name); state in \(stateURL.path)")
    let started = Date()
    var last = ""
    while Date().timeIntervalSince(started) < minutes * 60 {
        let screen = render(splark, showText: showText)
        if screen != last {
            print("\n\(Date().formatted(date: .omitted, time: .standard))  \(screen)")
            last = screen
        }
        try await Task.sleep(for: .seconds(5))
    }
    await splark.stop()
    let items = splark.inbox.items
    print("\nDone. \(items.count) items: \(TriageLevel.allCases.map { level in "\(items.filter { $0.level == level }.count) \(level.rawValue)" }.joined(separator: ", ")); \(items.filter(\.byAI).count) summarised by ChatGPT.")
}

@MainActor private func render(_ splark: SplarkEngine, showText: Bool) -> String {
    let summary = splark.inbox.summary
    var lines = ["\(summary.headline) · spark \(summary.spark.rawValue) · \(splark.triageState)"]
    for (team, status) in splark.syncStatus.sorted(by: { $0.key < $1.key }) {
        lines.append("  \(team): \(status.progress.checked) of \(status.progress.total) checked\(status.problem.map { " · \($0)" } ?? "")\(status.missingScope ? " · reconnect to grant new permissions" : "")")
    }
    for item in splark.inbox.items {
        let mark = ["action": "[A]", "question": "[Q]", "fyi": "[ ]"][item.level.rawValue]!
        let meta = "\(item.newest.formatted(date: .omitted, time: .shortened)) · \(item.source)\(item.workspaceLabel.map { " · \($0)" } ?? "")"
        let text = showText ? " — \(item.lead) \(item.rest)" : ""
        lines.append("  \(mark) \(meta)\(item.byAI ? "" : " (heuristic)")\(text)")
    }
    return lines.joined(separator: "\n")
}
