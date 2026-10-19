import Foundation
import Testing
@testable import SplarkKit
@testable import SplarkUI

let now = Date(timeIntervalSince1970: 1_800_000_000)
func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
let lumen = Workspace(teamId: "T1", name: "Lumen", userId: "U1", userName: "ivan", url: nil, redirectPort: 53682, appId: "A1")
let community = Workspace(teamId: "T2", name: "Lumen Community", userId: "U9", userName: "ivan", url: nil, redirectPort: nil, appId: nil)

/// Waits for `condition`, polling, for up to `timeout` of real time.
@MainActor func eventually(_ timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

/// An inbox item, built the way the app builds them: a snapshot and a summary through `InboxStore`.
@MainActor func item(kind: SnapshotKind = .channel, title: String = "#incidents", team: String = "T1", newest: TimeInterval = 240,
                     replied: Bool = false, reactions: [Reaction] = []) -> InboxItem {
    let key = ItemKey(teamId: team, channelId: "C1", threadTs: kind == .thread ? "1.0" : nil)
    let ts = SlackTS.ts(ago(newest))
    let snapshot = ConversationSnapshot(key: key, kind: kind, title: title,
                                        unread: [SnapshotMessage(ts: ts, authorId: "U2", author: "Marta Ruiz", text: "can I roll back?", mentionsMe: false)],
                                        context: [], moreUnread: false)
    let store = InboxStore()
    store.setWorkspaces([lumen, community])
    var update = SyncUpdate()
    update.upsert(snapshot)
    store.apply(update)
    store.apply([TriageResult(key: key, newestTs: ts, items: [TriageItem(level: .action, lead: "Approve the rollback?", rest: "", reason: "", anchorTs: ts, byAI: true)])])
    if replied { store.markReplied(key) }
    for r in reactions { store.addReaction(r, to: store.items[0].id) }
    return store.items[0]
}

@MainActor @Suite struct PresenterTests {
    @Test(arguments: [
        (10.0, "now"), (59, "now"), (60, "1m"), (240, "4m"), (3599, "59m"), (3600, "1h"), (7200 + 1800, "2h"), (86399, "23h"),
        (86400, "1d"), (6 * 86400, "6d"),
    ] as [(TimeInterval, String)])
    func shortTimes(secondsAgo: TimeInterval, text: String) {
        #expect(Presenter.shortTime(ago(secondsAgo), now: now) == text)
    }

    @Test func aWeekOrMoreShowsTheDate() {
        let date = ago(10 * 86400)
        #expect(Presenter.shortTime(date, now: now) == date.formatted(.dateTime.day().month(.abbreviated)))
    }

    @Test func metaLines() {
        #expect(Presenter.metaLine(item(), now: now) == "4m · #incidents")
        #expect(Presenter.metaLine(item(kind: .thread, title: "#marketing", newest: 2400, reactions: [.eyes]), now: now) == "40m · thread in #marketing · 👀")
        #expect(Presenter.metaLine(item(kind: .dm, title: "Daniel Cho", newest: 1500, replied: true), now: now) == "25m · Daniel Cho · replied")
        #expect(Presenter.metaLine(item(title: "#help", team: "T2", newest: 7200), now: now) == "2h · #help · Lumen Community")
    }

    @Test func headerIsQuietWhenNothingIsHappening() {
        let done = SyncStatus(problem: nil, progress: .init(checked: 300, total: 300))
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": done], triage: .idle, now: now) == nil)
    }

    @Test func headerSaysWhatSplarkIsDoingMostImportantFirst() {
        let catching = SyncStatus(problem: nil, progress: .init(checked: 120, total: 300))
        let other = SyncStatus(problem: nil, progress: .init(checked: 5, total: 10))
        #expect(Presenter.headerStatus(workspaces: [lumen, community], sync: ["T1": catching, "T2": other], triage: .summarising(3), now: now)
                == HeaderStatus(text: "Catching up… 125 of 310 conversations", working: true))
        let done = SyncStatus(problem: nil, progress: .init(checked: 3, total: 3))
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": done], triage: .summarising(1), now: now)
                == HeaderStatus(text: "Summarising 1 conversation", working: true))
        let offline = SyncStatus(problem: .offline(retryAt: now), progress: .init(checked: 1, total: 3))
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": offline], triage: .summarising(2), now: now)
                == HeaderStatus(text: "Offline, showing last results", working: false))
    }

    @Test(arguments: [
        (TriagePause.byUser, "Summaries paused"),
        (.signedOut, "Summaries paused: sign in again"),
        (.notEligible, "Summaries off: this ChatGPT plan can't be used"),
    ])
    func summaryPauses(pause: TriagePause, text: String) {
        #expect(Presenter.headerStatus(workspaces: [], sync: [:], triage: .paused(pause), now: now) == HeaderStatus(text: text, working: false))
    }

    @Test func pausesUntilATimeSayWhen() {
        let at = Calendar.current.date(bySettingHour: 15, minute: 40, second: 0, of: now)!
        let clock = at.formatted(date: .omitted, time: .shortened)
        #expect(Presenter.headerStatus(workspaces: [], sync: [:], triage: .paused(.usageLimit(until: at)), now: now)?.text
                == "Summaries paused: ChatGPT usage limit, back at \(clock)")
        #expect(Presenter.headerStatus(workspaces: [], sync: [:], triage: .paused(.budget(until: at)), now: now)?.text == "Summaries paused until \(clock)")
    }

    @Test func workspaceProblemsReachTheHeader() {
        let revoked = SyncStatus(problem: .tokenRevoked)
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": revoked], triage: .idle, now: now)?.text == "Lumen needs reconnecting in Settings")
        let pasted = SyncStatus(problem: .reauthorize)
        #expect(Presenter.headerStatus(workspaces: [community], sync: ["T2": pasted], triage: .idle, now: now)?.text
                == "Lumen Community's token stopped working: paste a new one in Settings")
        var scope = SyncStatus()
        scope.missingScope = true
        scope.progress = .init(checked: 1, total: 1)
        #expect(Presenter.headerStatus(workspaces: [lumen], sync: ["T1": scope], triage: .idle, now: now)?.text == "Reconnect Lumen to grant new permissions")
    }

    @Test func theMenuBarShowsTheLevelAndHowManyNeedYou() {
        let three = InboxSummary(needYou: 3, spark: .bright, headline: "3 need you", comments: 1)
        #expect(Presenter.statusItem(three, showCount: true) == StatusItemContent(level: .bright, count: "3", accessibility: "Splark: 3 need you"))
        #expect(Presenter.statusItem(three, showCount: false).count == nil)
        let calm = InboxSummary(needYou: 0, spark: .dimmed, headline: "Nothing needs you", comments: 4)
        #expect(Presenter.statusItem(calm, showCount: true) == StatusItemContent(level: .dimmed, count: nil, accessibility: "Splark: Nothing needs you"))
    }

    @Test func workspaceStatusForSettings() {
        var synced = SyncStatus()
        synced.lastSuccess = ago(120)
        #expect(Presenter.workspaceStatus(lumen, sync: synced, now: now) == WorkspaceStatusText(title: "Connected", detail: "Synced 2m ago"))
        #expect(Presenter.workspaceStatus(lumen, sync: nil, now: now) == WorkspaceStatusText(title: "Connected", detail: "Not synced yet"))
        #expect(Presenter.workspaceStatus(lumen, sync: SyncStatus(problem: .tokenRevoked), now: now).title == "Token revoked")
        #expect(Presenter.workspaceStatus(lumen, sync: SyncStatus(problem: .reauthorize), now: now).title == "Reconnect needed")
        #expect(Presenter.workspaceStatus(community, sync: SyncStatus(problem: .reauthorize), now: now).title == "Token expired")
        #expect(Presenter.workspaceStatus(lumen, sync: SyncStatus(problem: .offline(retryAt: now)), now: now).title == "Offline")
    }
}
