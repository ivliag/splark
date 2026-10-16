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

@Suite struct ProcessRunnerTests {
    @Test func returnsStandardOutput() throws {
        #expect(try ProcessRunner().run("/bin/echo", ["hi"]) == "hi\n")
    }

    @Test func killsAToolThatHangs() throws {
        let started = Date()
        #expect(throws: ProcessRunnerError.timedOut("/bin/sleep")) { try ProcessRunner(timeout: 0.3).run("/bin/sleep", ["5"]) }
        #expect(Date().timeIntervalSince(started) < 2)
    }
}

@Suite struct BadgeWatcherLifecycleTests {
    final class CountingRunner: CommandRunner, @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var calls: Int { lock.withLock { count } }
        func run(_ executable: String, _ arguments: [String]) throws -> String {
            lock.withLock { count += 1 }
            return #""StatusLabel"={ "label"="" }"#
        }
    }

    @Test func racingStartsAndStopsLeaveNothingPolling() async throws {
        let runner = CountingRunner()
        let watcher = BadgeWatcher(runner: runner, interval: .milliseconds(5), isSlackRunning: { true })
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 { group.addTask { if i.isMultiple(of: 2) { watcher.start { _ in } } else { watcher.stop() } } }
        }
        watcher.stop()
        #expect(!watcher.isRunning)
        try await Task.sleep(for: .milliseconds(50))
        let settled = runner.calls
        try await Task.sleep(for: .milliseconds(100))
        #expect(runner.calls == settled)
    }
}
