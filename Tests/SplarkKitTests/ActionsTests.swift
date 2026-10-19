import Foundation
import Observation
import Testing
@testable import SplarkKit

final class Opened: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ url: URL) { lock.withLock { urls.append(url) } }
    var all: [URL] { lock.withLock { urls } }
}

@MainActor @Suite struct ActionsTests {
    let clock = ManualClock()
    let slack = FakeSlack()
    let opened = Opened()

    init() {
        slack.addUser("U2", "Marta Ruiz")
        slack.addChannel("D1", kind: .im, user: "U2", lastRead: ts(-1000))
        slack.post("D1", slackMessage(ts(-600), user: "U2", text: "can you approve?"))
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-1000))
        slack.post("C1", slackMessage(ts(-500), user: "U2", text: "<@U1> is the copy final?"))
        slack.addChannel("C2", kind: .publicChannel, name: "random", lastRead: ts(-1000))
        slack.post("C2", slackMessage(ts(-400), user: "U3", text: "coffee?"))
        slack.post("C2", slackMessage(ts(-3000), user: "U2", text: "release plan?", replyCount: 1, latestReply: ts(-60), replyUsers: ["U1"]))
        slack.reply("C2", thread: ts(-3000), slackMessage(ts(-2000), user: "U1", text: "draft", threadTs: ts(-3000)))
        slack.reply("C2", thread: ts(-3000), slackMessage(ts(-60), user: "U2", text: "done?", threadTs: ts(-3000)))
    }

    func setUp(undo: Duration = .seconds(3600), opens: Bool = true) async -> (Actions, InboxStore, SyncEngine) {
        let engine = makeEngine(slack, clock)
        let inbox = InboxStore()
        inbox.setWorkspaces([lumen])
        inbox.apply(await engine.runUntilIdle())
        let opened = self.opened
        let actions = Actions(inbox: inbox, targets: { [slack] team in team == "T1" ? ActionTarget(slack: slack, engine: engine) : nil },
                              undoWindow: undo, open: { url in opened.add(url); return opens || url.scheme != "slack" })
        return (actions, inbox, engine)
    }

    func item(_ inbox: InboxStore, _ channel: String, thread: Bool = false) -> InboxItem {
        inbox.items.first { $0.key.channelId == channel && ($0.key.threadTs != nil) == thread }!
    }

    @Test func aChannelReplyGoesInTheThreadOfItsMessage() async throws {
        let (actions, inbox, engine) = await setUp()
        try await actions.reply(to: item(inbox, "C1"), text: " on it ")
        #expect(slack.posted.map { "\($0.channel) \($0.text) \($0.threadTs ?? "-")" } == ["C1 on it \(ts(-500))"])
        #expect(item(inbox, "C1").replied)
        #expect(await engine.memory.threads.watch(channelId: "C1", threadTs: ts(-500)) != nil)
    }

    @Test func aDMReplyIsDirectAndAThreadReplyStaysInItsThread() async throws {
        let (actions, inbox, _) = await setUp()
        try await actions.reply(to: item(inbox, "D1"), text: "approved")
        try await actions.reply(to: item(inbox, "C2", thread: true), text: "yes")
        #expect(slack.posted.map(\.threadTs) == [nil, ts(-3000)])
    }

    @Test func aFailedReplyIsUndoneAndReported() async {
        let (actions, inbox, _) = await setUp()
        slack.fail("chat.postMessage", with: SlackError.api("is_archived"))
        await #expect(throws: ActionError.slack("is_archived")) { try await actions.reply(to: item(inbox, "C1"), text: "hi") }
        #expect(!item(inbox, "C1").replied)
    }

    @Test func reactionsShowAtOnceAndRollBackOnFailure() async throws {
        let (actions, inbox, _) = await setUp()
        try await actions.react(to: item(inbox, "C1"), with: .eyes)
        #expect(item(inbox, "C1").reactions == [.eyes])
        #expect(slack.reactions.map { "\($0.channel) \($0.ts) \($0.name)" } == ["C1 \(ts(-500)) eyes"])
        slack.fail("reactions.add", with: SlackError.api("already_reacted"))
        try await actions.react(to: item(inbox, "D1"), with: .thumbsUp)          // already there in Slack: fine
        #expect(item(inbox, "D1").reactions == [.thumbsUp])
        slack.fail("reactions.add", with: URLError(.notConnectedToInternet))
        await #expect(throws: ActionError.self) { try await actions.react(to: item(inbox, "D1"), with: .whiteCheckMark) }
        #expect(item(inbox, "D1").reactions == [.thumbsUp])
    }

    @Test func markReadHidesAtOnceAndTellsSlackAfterTheUndoWindow() async {
        let (actions, inbox, _) = await setUp()
        actions.markRead([item(inbox, "D1")])
        #expect(!inbox.items.contains { $0.key.channelId == "D1" })
        #expect(!slack.calls.contains("conversations.mark D1"))
        await actions.commitPendingReads()
        #expect(slack.lastRead("D1") == ts(-600))
    }

    @Test func undoBringsItBackAndSlackHearsNothing() async {
        let (actions, inbox, _) = await setUp()
        let token = actions.markRead([item(inbox, "D1")])
        actions.undo(token)
        await actions.commitPendingReads()
        #expect(inbox.items.contains { $0.key.channelId == "D1" })
        #expect(!slack.calls.contains("conversations.mark D1"))
    }

    @Test func theUndoWindowClosesByItself() async throws {
        let (actions, inbox, _) = await setUp(undo: .milliseconds(20))
        actions.markRead([item(inbox, "D1")])
        #expect(await eventually { slack.calls.contains("conversations.mark D1") })
    }

    @Test func aFailedMarkReadBringsTheItemBackAndSaysSo() async {
        let (actions, inbox, _) = await setUp()
        slack.fail("conversations.mark", with: SlackError.api("not_in_channel"))
        actions.markRead([item(inbox, "D1")])
        await actions.commitPendingReads()
        #expect(inbox.items.contains { $0.key.channelId == "D1" })
        #expect(actions.lastFailure?.key == item(inbox, "D1").key)
        #expect(actions.lastFailure?.message == "Couldn't mark it as read. Try again.")
    }

    /// The same failure twice in a row reaches the toast twice: setting an equal value again wouldn't tell observers.
    @Test func theSameFailureTwiceIsReportedTwice() async {
        let (actions, inbox, _) = await setUp()
        slack.fail("conversations.mark", with: SlackError.api("not_in_channel"))
        let reported = LockedBox(0)
        for _ in 0..<2 {
            withObservationTracking { _ = actions.lastFailure } onChange: { reported.withLock { $0 += 1 } }
            actions.markRead([item(inbox, "D1")])
            await actions.commitPendingReads()
        }
        #expect(reported.value == 2)
    }

    @Test func markingAThreadReadMovesOnlySplarksOwnLine() async {
        let (actions, inbox, engine) = await setUp()
        actions.markRead([item(inbox, "C2", thread: true)])
        await actions.commitPendingReads()
        #expect(!slack.calls.contains { $0.hasPrefix("conversations.mark") })
        #expect(await engine.memory.threads.watch(channelId: "C2", threadTs: ts(-3000))?.seenThrough == ts(-60))
    }

    @Test func markAllCommentsReadLeavesWhatNeedsYou() async {
        let (actions, inbox, _) = await setUp()
        actions.markAllCommentsRead()
        #expect(inbox.items.allSatisfy { $0.level != .fyi })
        #expect(inbox.items.contains { $0.key.channelId == "D1" })
        await actions.commitPendingReads()
        #expect(slack.calls.contains("conversations.mark C2"))
    }

    @Test func openingUsesSlacksLinkThenThePermalink() async {
        let (actions, inbox, _) = await setUp(opens: false)
        await actions.open(item(inbox, "C2", thread: true))
        #expect(opened.all.map(\.absoluteString) == [
            "slack://channel?team=T1&id=C2&message=\(ts(-60))&thread_ts=\(ts(-3000))",
            "https://lumen.slack.com/archives/C2/p\(ts(-60).replacingOccurrences(of: ".", with: ""))",
        ])
    }

    @Test func aTopLevelMessageLinkHasNoThread() {
        #expect(DeepLink.slack(teamId: "T1", channelId: "C1", messageTs: "1.000100", threadTs: nil).absoluteString
                == "slack://channel?team=T1&id=C1&message=1.000100")
    }
}
