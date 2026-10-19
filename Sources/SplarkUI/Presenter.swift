import Foundation
import SplarkKit

/// The panel header's second line: what Splark is doing, or what's wrong (spec §4.3, §9).
public struct HeaderStatus: Equatable, Sendable {
    public let text: String
    public let working: Bool   // shows the cycling spark
}

/// What the menu-bar item shows (spec §4.2).
public struct StatusItemContent: Equatable, Sendable {
    public let level: SparkLevel
    public let count: String?
    public let accessibility: String
}

/// A workspace's line in Settings (spec §4.5).
public struct WorkspaceStatusText: Equatable, Sendable {
    public let title: String
    public let detail: String
}

/// The words the UI shows, as pure functions of the engine's state.
public enum Presenter {
    /// "now", "4m", "1h", "3d", then the date.
    public static func shortTime(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        case ..<(7 * 86400): return "\(Int(seconds / 86400))d"
        default: return date.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// A clock time in the user's format: "14:05" or "2:05 PM".
    public static func clockTime(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

    /// "4m · #incidents", "40m · thread in #marketing · 👀", "2h · #help · Lumen Community", "25m · Daniel Cho · replied".
    public static func metaLine(_ item: InboxItem, now: Date) -> String {
        var parts = [shortTime(item.newest, now: now), item.source]
        if let workspace = item.workspaceLabel { parts.append(workspace) }
        if item.replied { parts.append("replied") }
        if !item.reactions.isEmpty { parts.append(item.reactions.map(\.emoji).joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }

    /// The header's second line, most important first: offline, a workspace to reconnect, catching up, summaries,
    /// missing permissions. Nil when there is nothing to say.
    public static func headerStatus(workspaces: [Workspace], sync: [String: SyncStatus], triage: TriageState, now: Date) -> HeaderStatus? {
        let statuses = workspaces.compactMap { workspace in sync[workspace.teamId].map { (workspace, $0) } }
        if statuses.contains(where: { if case .offline? = $0.1.problem { true } else { false } }) {
            return HeaderStatus(text: "Offline, showing last results", working: false)
        }
        if let (workspace, status) = statuses.first(where: { $0.1.problem?.stopsSync == true }) {
            if status.problem == .reauthorize, workspace.redirectPort == nil {
                return HeaderStatus(text: "\(workspace.name)'s token stopped working: paste a new one in Settings", working: false)
            }
            return HeaderStatus(text: "\(workspace.name) needs reconnecting in Settings", working: false)
        }
        let checked = statuses.reduce(0) { $0 + $1.1.progress.checked }, total = statuses.reduce(0) { $0 + $1.1.progress.total }
        if total > 0, checked < total {
            return HeaderStatus(text: "Catching up… \(checked) of \(total) conversations", working: true)
        }
        switch triage {
        case .summarising(let count):
            return HeaderStatus(text: "Summarising \(count) conversation\(count == 1 ? "" : "s")", working: true)
        case .paused(.byUser): return HeaderStatus(text: "Summaries paused", working: false)
        case .paused(.signedOut): return HeaderStatus(text: "Summaries paused: sign in again", working: false)
        case .paused(.notEligible): return HeaderStatus(text: "Summaries off: this ChatGPT plan can't be used", working: false)
        case .paused(.usageLimit(let until)):
            return HeaderStatus(text: "Summaries paused: ChatGPT usage limit, back at \(clockTime(until))", working: false)
        case .paused(.budget(let until)): return HeaderStatus(text: "Summaries paused until \(clockTime(until))", working: false)
        case .idle: break
        }
        if let (workspace, _) = statuses.first(where: { $0.1.missingScope }) {
            return HeaderStatus(text: "Reconnect \(workspace.name) to grant new permissions", working: false)
        }
        return nil
    }

    public static func statusItem(_ summary: InboxSummary, showCount: Bool) -> StatusItemContent {
        StatusItemContent(level: summary.spark, count: showCount && summary.needYou > 0 ? String(summary.needYou) : nil,
                          accessibility: "Splark: \(summary.headline)")
    }

    public static func workspaceStatus(_ workspace: Workspace, sync: SyncStatus?, now: Date) -> WorkspaceStatusText {
        let detail = sync?.lastSuccess.map { "Synced \(shortTime($0, now: now) == "now" ? "just now" : shortTime($0, now: now) + " ago")" } ?? "Not synced yet"
        switch sync?.problem {
        case .tokenRevoked?: return WorkspaceStatusText(title: "Token revoked", detail: detail)
        case .reauthorize?: return WorkspaceStatusText(title: workspace.redirectPort == nil ? "Token expired" : "Reconnect needed", detail: detail)
        case .offline?: return WorkspaceStatusText(title: "Offline", detail: detail)
        case nil: return WorkspaceStatusText(title: sync?.missingScope == true ? "Needs new permissions" : "Connected", detail: detail)
        }
    }
}
