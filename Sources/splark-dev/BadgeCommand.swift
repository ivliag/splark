import Foundation
import SplarkKit

func badgeCommand() async {
    let seconds = Int(option("--seconds") ?? "20") ?? 20
    let watcher = BadgeWatcher()
    print("Watching Slack's badge for \(seconds) s (change it in Slack to see updates)…")
    watcher.start { badge in print("\(Date().formatted(date: .omitted, time: .standard))  \(badge.map { "\($0)" } ?? "unavailable (Slack not running?)")") }
    try? await Task.sleep(for: .seconds(seconds))
    watcher.stop()
}
