import AppKit

/// What Slack's Dock badge currently says. `nil` (as `SlackBadge?`) means unavailable: Slack isn't running or the badge can't be read.
public enum SlackBadge: Equatable, Sendable {
    case clear         // no badge: nothing unread (named so it never collides with Optional.none)
    case dot           // "•": unread activity, nothing for you specifically
    case count(Int)    // DMs, mentions, keywords, followed threads

    /// Parses `lsappinfo info -only StatusLabel …` output. Returns nil when there is no StatusLabel line.
    public static func parse(lsappinfoOutput output: String) -> SlackBadge? {
        guard let range = output.range(of: #""label"="([^"]*)""#, options: .regularExpression) else { return nil }
        let label = output[range].dropFirst("\"label\"=\"".count).dropLast()
        if label.isEmpty { return .clear }
        let digits = label.prefix(while: \.isNumber)
        if let n = Int(digits) { return n > 0 ? .count(n) : .clear }   // "99+" → 99
        return .dot
    }
}

public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> String
}

public enum ProcessRunnerError: Error, Equatable { case timedOut(String) }

public struct ProcessRunner: CommandRunner {
    public let timeout: TimeInterval
    public init(timeout: TimeInterval = 5) { self.timeout = timeout }

    /// Returns the tool's standard output. A tool still running after `timeout` is killed and `.timedOut` is thrown.
    public func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        // Read on another thread, so a chatty tool can't fill the pipe and stall.
        let output = LockedBox(Data())
        let readDone = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        try process.run()
        DispatchQueue.global().async {
            output.value = reader.readDataToEndOfFile()
            readDone.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw ProcessRunnerError.timedOut(executable)
        }
        readDone.wait()
        return String(decoding: output.value, as: UTF8.self)
    }
}

/// Polls Slack's Dock badge via `lsappinfo` (no permissions needed) while Slack is running.
public final class BadgeWatcher: @unchecked Sendable {
    public static let slackBundleID = "com.tinyspeck.slackmacgap"
    private let runner: CommandRunner
    private let isSlackRunning: @Sendable () -> Bool
    private let interval: Duration
    private let task = LockedBox<Task<Void, Never>?>(nil)

    public init(runner: CommandRunner = ProcessRunner(),
                interval: Duration = .seconds(2),
                isSlackRunning: @escaping @Sendable () -> Bool = {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: BadgeWatcher.slackBundleID).isEmpty
                }) {
        self.runner = runner
        self.interval = interval
        self.isSlackRunning = isSlackRunning
    }

    /// nil = Slack isn't running, or the badge can't be read.
    public func current() -> SlackBadge? {
        guard isSlackRunning(),
              let output = try? runner.run("/usr/bin/lsappinfo", ["info", "-only", "StatusLabel", "-app", Self.slackBundleID])
        else { return nil }
        return SlackBadge.parse(lsappinfoOutput: output)
    }

    /// Calls `onChange` with the first reading and then on every change, until `stop()`.
    public func start(onChange: @escaping @Sendable (SlackBadge?) -> Void) {
        let poller = Task { [weak self] in
            var last: SlackBadge?? = .none
            while !Task.isCancelled, let self {
                let now = self.current()
                if last != .some(now) { last = .some(now); onChange(now) }
                try? await Task.sleep(for: self.interval)
            }
        }
        task.exchange(poller)?.cancel()
    }

    public func stop() { task.exchange(nil)?.cancel() }

    public var isRunning: Bool { task.value != nil }
}
