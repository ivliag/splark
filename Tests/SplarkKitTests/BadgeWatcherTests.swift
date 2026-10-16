import Foundation
import Testing
@testable import SplarkKit

@Suite struct BadgeWatcherTests {
    @Test(arguments: [
        (#""StatusLabel"={ "label"="" }"#, SlackBadge?.some(.clear)),
        (#""StatusLabel"={ "label"="•" }"#, .some(.dot)),
        (#""StatusLabel"={ "label"="12" }"#, .some(.count(12))),
        (#""StatusLabel"={ "label"="0" }"#, .some(.clear)),
        (#""StatusLabel"={ "label"="!" }"#, .some(.dot)),
        (#""StatusLabel"={ "label"="99+" }"#, .some(.count(99))),
        ("", nil),
    ])
    func parsesLsappinfoOutput(output: String, expected: SlackBadge?) {
        #expect(SlackBadge.parse(lsappinfoOutput: output) == expected)
    }

    struct FakeRunner: CommandRunner {
        let output: String
        func run(_ executable: String, _ arguments: [String]) throws -> String {
            precondition(executable == "/usr/bin/lsappinfo" && arguments == ["info", "-only", "StatusLabel", "-app", "com.tinyspeck.slackmacgap"])
            return output
        }
    }

    @Test func readsBadgeOnlyWhileSlackRuns() {
        let running = BadgeWatcher(runner: FakeRunner(output: #""StatusLabel"={ "label"="3" }"#), isSlackRunning: { true })
        #expect(running.current() == .count(3))
        let notRunning = BadgeWatcher(runner: FakeRunner(output: #""StatusLabel"={ "label"="3" }"#), isSlackRunning: { false })
        #expect(notRunning.current() == nil)
    }

    @Test func startReportsFirstReadingThenOnlyChanges() async throws {
        final class Box: @unchecked Sendable { let lock = NSLock(); var seen: [SlackBadge?] = [] }
        let box = Box()
        let watcher = BadgeWatcher(runner: FakeRunner(output: #""StatusLabel"={ "label"="•" }"#), interval: .milliseconds(20), isSlackRunning: { true })
        watcher.start { badge in box.lock.withLock { box.seen.append(badge) } }
        try await Task.sleep(for: .milliseconds(150))
        watcher.stop()
        #expect(box.lock.withLock { box.seen } == [.dot])
    }
}
