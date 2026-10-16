import AppKit

/// What Slack's Dock badge currently says.
public enum SlackBadge: Equatable, Sendable {
    case none          // no badge
    case dot           // "•": unread activity, nothing for you specifically
    case count(Int)    // DMs, mentions, keywords, followed threads

    /// Parses `lsappinfo info -only StatusLabel …` output. Returns nil when there is no StatusLabel line.
    public static func parse(lsappinfoOutput output: String) -> SlackBadge? {
        guard let range = output.range(of: #""label"="([^"]*)""#, options: .regularExpression) else { return nil }
        let label = output[range].dropFirst("\"label\"=\"".count).dropLast()
        if label.isEmpty { return SlackBadge.none }
        let digits = label.prefix(while: \.isNumber)
        if let n = Int(digits) { return n > 0 ? .count(n) : SlackBadge.none }   // "99+" → 99
        return .dot
    }
}

public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) throws -> String
}

public struct ProcessRunner: CommandRunner {
    public init() {}
    public func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Polls Slack's Dock badge via `lsappinfo` (no permissions needed) while Slack is running.
public final class BadgeWatcher: @unchecked Sendable {
    public static let slackBundleID = "com.tinyspeck.slackmacgap"
    private let runner: CommandRunner
    private let isSlackRunning: @Sendable () -> Bool
    private let interval: Duration
    private var task: Task<Void, Never>?

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
        stop()
        task = Task { [weak self] in
            var last: SlackBadge?? = .none
            while !Task.isCancelled, let self {
                let now = self.current()
                if last != .some(now) { last = .some(now); onChange(now) }
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }
}
