import Foundation
import Testing
@testable import SplarkKit

/// Slack timestamps around the test clock's start (1 800 000 000): ts(-60) is a minute earlier.
func ts(_ offset: Int) -> String { String(format: "%d.000000", 1_800_000_000 + offset) }

let lumen = Workspace(teamId: "T1", name: "Lumen", userId: "U1", userName: "ivan", url: "https://lumen.slack.com/", redirectPort: nil, appId: nil)

func makeEngine(_ slack: FakeSlack, _ clock: ManualClock, memory: SyncMemory = SyncMemory(), excluded: Set<String> = []) -> SyncEngine {
    SyncEngine(workspace: lumen, slack: slack, names: UserDirectory(now: { clock.now }) { try await slack.usersInfo($0) },
               memory: memory, excluded: excluded, now: { clock.now })
}

extension SyncEngine {
    /// Runs steps until nothing is due, as the app's loop would between sleeps.
    func runUntilIdle() async -> SyncUpdate {
        var all = SyncUpdate()
        for _ in 0..<1000 {
            let step = await step()
            all.merge(step.update)
            if !step.didWork { break }
        }
        return all
    }
}

@Suite struct SyncEngineConversationTests {
    let clock = ManualClock()
    let c1 = ItemKey(teamId: "T1", channelId: "C1")

    func channelWithSevenMessages(lastRead: String?) -> FakeSlack {
        let slack = FakeSlack()
        slack.addUser("U2", "Marta Ruiz")
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: lastRead)
        for (i, offset) in [-900, -800, -700, -600, -500, -400, -300].enumerated() {
            slack.post("C1", slackMessage(ts(offset), user: "U2", text: "m\(i)"))
        }
        return slack
    }

    @Test func findsTheMessagesAfterLastReadWithThreeEarlierForContext() async throws {
        let engine = makeEngine(channelWithSevenMessages(lastRead: ts(-500)), clock)
        let snapshot = try #require(await engine.runUntilIdle().upserted[c1])
        #expect(snapshot.unread.map(\.text) == ["m5", "m6"])
        #expect(snapshot.context.map(\.text) == ["m2", "m3", "m4"])
        #expect(snapshot.title == "#eng" && snapshot.kind == .channel && !snapshot.moreUnread)
        #expect(snapshot.unread[0].author == "Marta Ruiz")
    }

    @Test func theUsersOwnMessagesCountAsRead() async {
        let slack = channelWithSevenMessages(lastRead: ts(-400))
        slack.post("C1", slackMessage(ts(-200), user: "U1", text: "mine"))
        let engine = makeEngine(slack, clock)
        #expect(await engine.runUntilIdle().upserted[c1]?.unread.map(\.text) == ["m6"])
        slack.setLastRead("C1", ts(-300))
        clock.advance(400)
        #expect(await engine.runUntilIdle().removed == [c1])
    }

    @Test func joinsAndTopicChangesAreNotMessages() async {
        let slack = channelWithSevenMessages(lastRead: ts(-300))
        slack.post("C1", slackMessage(ts(-100), user: "U3", text: "<@U3> has joined", subtype: "channel_join"))
        slack.post("C1", slackMessage(ts(-90), user: nil, text: "deployed", subtype: "bot_message", botId: "B1", botName: "Deploybot"))
        let snapshot = await makeEngine(slack, clock).runUntilIdle().upserted[c1]
        #expect(snapshot?.unread.map(\.author) == ["Deploybot"])
    }

    @Test func aDMThatWasNeverOpenedUsesSlacksUnreadCount() async {
        let slack = FakeSlack()
        slack.addChannel("D1", kind: .im, user: "U2", lastRead: nil, unreadCountDisplay: 2)
        slack.addChannel("D2", kind: .im, user: "U3", lastRead: nil, unreadCountDisplay: 0)
        for offset in [-300, -200, -100] {
            slack.post("D1", slackMessage(ts(offset), user: "U2", text: "\(offset)"))
            slack.post("D2", slackMessage(ts(offset), user: "U3", text: "\(offset)"))
        }
        let update = await makeEngine(slack, clock).runUntilIdle()
        #expect(update.upserted[ItemKey(teamId: "T1", channelId: "D1")]?.unread.map(\.text) == ["-200", "-100"])
        #expect(update.upserted[ItemKey(teamId: "T1", channelId: "D1")]?.kind == .dm)
        #expect(!slack.calls.contains("conversations.history D2"))
    }

    @Test func aColdStartChecksDirectMessagesFirst() async {
        let slack = FakeSlack()
        slack.addChannel("C1", kind: .publicChannel, name: "eng")
        slack.addChannel("G1", kind: .privateChannel, name: "leads")
        slack.addChannel("M1", kind: .mpim, name: "mpdm-marta--ivan--leo-1")
        slack.addChannel("D1", kind: .im, user: "U2")
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        #expect(slack.calls.filter { $0.hasPrefix("conversations.info") } == ["conversations.info D1", "conversations.info M1", "conversations.info G1", "conversations.info C1"])
        #expect(await engine.status.progress == SyncSchedule.Progress(checked: 4, total: 4))
    }

    @Test func anUnchangedConversationIsNotSentAgain() async {
        let slack = channelWithSevenMessages(lastRead: ts(-500))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        slack.clearCalls()
        clock.advance(61)
        #expect(await engine.runUntilIdle().isEmpty)
        #expect(slack.calls.filter { $0 == "conversations.history C1" }.count == 1)   // no second call for context
    }

    @Test func aMarkedReadConversationStaysHiddenUntilSomethingNewArrives() async {
        let slack = channelWithSevenMessages(lastRead: ts(-500))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        #expect(await engine.markedRead(c1, through: ts(-300)).removed == [c1])
        clock.advance(61)
        #expect(await engine.runUntilIdle().isEmpty)                 // Slack's last_read hasn't caught up yet
        slack.post("C1", slackMessage(ts(10), user: "U2", text: "new"))
        clock.advance(61)
        #expect(await engine.runUntilIdle().upserted[c1]?.unread.map(\.text) == ["new"])
    }

    @Test func aNewerMessageSurvivesAMarkReadForAnOlderOne() async throws {
        let engine = makeEngine(channelWithSevenMessages(lastRead: ts(-500)), clock)
        _ = await engine.runUntilIdle()
        let kept = try #require(await engine.markedRead(c1, through: ts(-400)).upserted[c1])   // m5 read, m6 arrived during the undo
        #expect(kept.unread.map(\.text) == ["m6"])
        #expect(kept.context.last?.text == "m5")
    }

    @Test func aConversationExcludedWhileItWasBeingCheckedStaysOut() async {
        let slack = channelWithSevenMessages(lastRead: ts(-500))
        let box = LockedBox<SyncEngine?>(nil)
        slack.onCall = { call in
            if call == "conversations.history C1", let engine = box.value { _ = await engine.setExcluded(["C1"]) }
        }
        let engine = makeEngine(slack, clock)
        box.value = engine
        #expect(await engine.runUntilIdle().upserted.isEmpty)
    }

    @Test func excludedChannelsAreNeitherFetchedNorShown() async {
        let slack = channelWithSevenMessages(lastRead: ts(-500))
        slack.addChannel("C2", kind: .publicChannel, name: "random", lastRead: ts(-1000))
        slack.post("C2", slackMessage(ts(-50), user: "U2", text: "hi"))
        let engine = makeEngine(slack, clock, excluded: ["C2"])
        let update = await engine.runUntilIdle()
        #expect(update.upserted.keys.map(\.channelId) == ["C1"])
        #expect(!slack.calls.contains { $0.hasSuffix("C2") })
        #expect(await engine.setExcluded(["C1"]).removed == [c1])
    }

    @Test func messagesOlderThanTwoWeeksAreLeftOut() async {
        let slack = FakeSlack()
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-30 * 86400))
        slack.post("C1", slackMessage(ts(-20 * 86400), user: "U2", text: "old"))
        slack.post("C1", slackMessage(ts(-60), user: "U2", text: "recent"))
        #expect(await makeEngine(slack, clock).runUntilIdle().upserted[c1]?.unread.map(\.text) == ["recent"])
    }
}

@Suite struct SyncEngineErrorTests {
    let clock = ManualClock()
    let c1 = ItemKey(teamId: "T1", channelId: "C1")

    func slackWithOneUnread() -> FakeSlack {
        let slack = FakeSlack()
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-100))
        slack.post("C1", slackMessage(ts(-50), user: "U2", text: "hi"))
        return slack
    }

    @Test func aRevokedTokenStopsTheWorkspaceAndClearsItsItems() async {
        let slack = slackWithOneUnread()
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        slack.fail("conversations.info", with: SlackError.api("token_revoked"))
        clock.advance(61)
        #expect(await engine.runUntilIdle().removed == [c1])
        #expect(await engine.status.problem == .tokenRevoked)
        let step = await engine.step()
        #expect(!step.didWork && step.nextWake == nil)
    }

    @Test func aRefusedRefreshAsksTheUserToReauthorize() async {
        let slack = slackWithOneUnread()
        slack.fail("users.conversations", with: SlackError.refreshFailed("invalid_refresh_token"))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        #expect(await engine.status.problem == .reauthorize)
    }

    @Test func aMissingScopeIsReportedButSyncingGoesOn() async {
        let slack = slackWithOneUnread()
        slack.addChannel("G1", kind: .privateChannel, name: "leads")
        slack.fail("conversations.info G1", with: SlackError.api("missing_scope"))
        let engine = makeEngine(slack, clock)
        #expect(await engine.runUntilIdle().upserted[c1] != nil)
        #expect(await engine.status.missingScope)
        slack.fail("conversations.info C1", with: URLError(.notConnectedToInternet))
        clock.advance(61)
        _ = await engine.runUntilIdle()
        #expect(await engine.status.missingScope)   // still there while offline
    }

    @Test func offlineBacksOffUpToFiveMinutesThenRecovers() async {
        let slack = slackWithOneUnread()
        slack.fail("users.conversations", with: URLError(.notConnectedToInternet))
        let engine = makeEngine(slack, clock)
        var delays: [TimeInterval] = []
        for _ in 0..<7 {
            _ = await engine.runUntilIdle()
            guard case .offline(let retryAt)? = await engine.status.problem else { Issue.record("not offline"); return }
            delays.append(retryAt.timeIntervalSince(clock.now))
            clock.advance(retryAt.timeIntervalSince(clock.now))
        }
        #expect(delays == [15, 30, 60, 120, 240, 300, 300])
        slack.fail("users.conversations", with: nil)
        #expect(await engine.runUntilIdle().upserted[c1] != nil)
        #expect(await engine.status.problem == nil)
    }

    @Test func aServerErrorCountsAsOffline() async {
        let slack = slackWithOneUnread()
        slack.fail("users.conversations", with: SlackError.http(503))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        #expect(await engine.status.problem == .offline(retryAt: clock.now.addingTimeInterval(15)))
    }

    @Test func aRateLimitDelaysOnlyThatConversation() async {
        let slack = slackWithOneUnread()
        slack.addChannel("C2", kind: .publicChannel, name: "random", lastRead: ts(-100))
        slack.post("C2", slackMessage(ts(-40), user: "U2", text: "yo"))
        slack.fail("conversations.info C1", with: SlackError.rateLimited(retryAfter: 42))
        let engine = makeEngine(slack, clock)
        let update = await engine.runUntilIdle()
        #expect(update.upserted.keys.map(\.channelId) == ["C2"])
        #expect(await engine.status.problem == nil)
        slack.fail("conversations.info C1", with: nil)
        clock.advance(42)
        #expect(await engine.runUntilIdle().upserted[c1] != nil)
    }

    @Test func aConversationThatIsGoneIsDropped() async {
        let slack = slackWithOneUnread()
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        slack.fail("conversations.info C1", with: SlackError.api("channel_not_found"))
        clock.advance(61)
        #expect(await engine.runUntilIdle().removed == [c1])
        slack.clearCalls()
        clock.advance(600)
        _ = await engine.runUntilIdle()
        #expect(!slack.calls.contains("conversations.info C1"))
    }
}

@Suite struct SyncEngineThreadTests {
    let clock = ManualClock()
    let parent = ts(-3000)
    var thread: ItemKey { ItemKey(teamId: "T1", channelId: "C1", threadTs: parent) }

    /// #eng with a thread Marta started and Ivan replied to; Marta has replied again since.
    func slackWithAThread(lastRead: String) -> FakeSlack {
        let slack = FakeSlack()
        slack.addUser("U2", "Marta Ruiz")
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: lastRead)
        slack.post("C1", slackMessage(parent, user: "U2", text: "release plan?", replyCount: 2, latestReply: ts(-60), replyUsers: ["U1", "U2"]))
        slack.reply("C1", thread: parent, slackMessage(ts(-2000), user: "U1", text: "draft is up", threadTs: parent))
        slack.reply("C1", thread: parent, slackMessage(ts(-60), user: "U2", text: "are we done?", threadTs: parent))
        return slack
    }

    @Test func repliesAfterTheUsersOwnReplyBecomeAThreadItem() async throws {
        let engine = makeEngine(slackWithAThread(lastRead: ts(-3500)), clock)
        let item = try #require(await engine.runUntilIdle().upserted[thread])
        #expect(item.kind == .thread && item.title == "#eng")
        #expect(item.unread.map(\.text) == ["are we done?"])
        #expect(item.context.first?.text == "release plan?")
    }

    @Test func theUsersRecentRepliesFoundBySearchStartAWatch() async {
        let slack = slackWithAThread(lastRead: ts(-10))   // the parent is read, so history won't show it
        slack.setSearch("from:<@U1>", [("C1", ts(-2000), parent)])
        #expect(await makeEngine(slack, clock).runUntilIdle().upserted[thread]?.unread.map(\.text) == ["are we done?"])
    }

    @Test func aMentionInAnOldThreadShowsJustTheMention() async {
        let slack = FakeSlack()
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-10))
        slack.post("C1", slackMessage(parent, user: "U2", text: "incident", replyCount: 2, latestReply: ts(-100)))
        slack.reply("C1", thread: parent, slackMessage(ts(-200), user: "U3", text: "looking"))
        slack.reply("C1", thread: parent, slackMessage(ts(-100), user: "U3", text: "<@U1> can you approve?"))
        slack.addChannel("C2", kind: .publicChannel, name: "ops", lastRead: ts(-10))
        slack.post("C2", slackMessage(ts(-3 * 86400), user: "U2", text: "old", replyCount: 1, latestReply: ts(-2 * 86400)))
        slack.reply("C2", thread: ts(-3 * 86400), slackMessage(ts(-2 * 86400), user: "U3", text: "<@U1> old ask"))
        slack.setSearch("<@U1>", [("C1", ts(-100), parent), ("C2", ts(-2 * 86400), ts(-3 * 86400))])
        let update = await makeEngine(slack, clock).runUntilIdle()
        #expect(update.upserted[thread]?.unread.map(\.mentionsMe) == [true])
        #expect(!slack.calls.contains("conversations.replies C2"))   // two days old: before the first sweep's look-back
    }

    @Test func aMentionOlderThanTheLookBackStaysOutOnLaterSweeps() async {
        let slack = FakeSlack()
        slack.addChannel("C2", kind: .publicChannel, name: "ops", lastRead: ts(-10))
        slack.post("C2", slackMessage(ts(-3 * 86400), user: "U2", text: "old", replyCount: 1, latestReply: ts(-2 * 86400)))
        slack.reply("C2", thread: ts(-3 * 86400), slackMessage(ts(-2 * 86400), user: "U3", text: "<@U1> old ask"))
        slack.setSearch("<@U1>", [("C2", ts(-2 * 86400), ts(-3 * 86400))])   // the newest mention is two days old, already read
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        clock.advance(120)                                                    // the second sweep
        _ = await engine.runUntilIdle()
        #expect(!slack.calls.contains("conversations.replies C2"))
    }

    @Test func aMentionSearchFindsLateIsStillHandled() async {
        let slack = FakeSlack()
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-10))
        slack.post("C1", slackMessage(parent, user: "U2", text: "incident", replyCount: 1, latestReply: ts(-100)))
        slack.reply("C1", thread: parent, slackMessage(ts(-100), user: "U3", text: "<@U1> can you approve?"))
        slack.setSearch("<@U1>", [("C1", ts(-20), nil)])                 // the first sweep sees a newer, top-level mention
        slack.setSearch("from:<@U1>", [("C9", ts(-5), ts(-50))])         // and one of the user's own messages, even newer
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        slack.setSearch("<@U1>", [("C1", ts(-20), nil), ("C1", ts(-100), parent)])   // the thread mention, indexed late
        clock.advance(120)
        #expect(await engine.runUntilIdle().upserted[thread] != nil)
    }

    @Test func theSweepWaitsForTheInventory() async {
        let slack = slackWithAThread(lastRead: ts(-3500))
        slack.fail("users.conversations", with: SlackError.rateLimited(retryAfter: 30))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        #expect(!slack.calls.contains("search.messages"))
        slack.fail("users.conversations", with: nil)
        clock.advance(30)
        _ = await engine.runUntilIdle()
        #expect(slack.calls.contains("search.messages"))
    }

    @Test func aLongThreadShowsItsNewestReplies() async throws {
        let slack = slackWithAThread(lastRead: ts(-3500))
        for i in 0..<45 { slack.reply("C1", thread: parent, slackMessage(ts(-50 + i), user: "U2", text: "r\(i)", threadTs: parent)) }
        let item = try #require(await makeEngine(slack, clock).runUntilIdle().upserted[thread])
        #expect(item.newestTs == ts(-6))
        #expect(item.unread.count == 46)
    }

    @Test func threadsWithNoItemYetAreClearedByATrustedClearBadge() async {
        let slack = FakeSlack()
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-3500))
        slack.post("C1", slackMessage(parent, user: "U2", text: "release plan?", replyCount: 1, latestReply: ts(-2000), replyUsers: ["U1"]))
        slack.reply("C1", thread: parent, slackMessage(ts(-2000), user: "U1", text: "draft is up", threadTs: parent))
        let engine = makeEngine(slack, clock)
        _ = await engine.badgeChanged(.dot)
        _ = await engine.runUntilIdle()
        slack.reply("C1", thread: parent, slackMessage(ts(-30), user: "U2", text: "thanks!", threadTs: parent))   // read in Slack before Splark looks
        _ = await engine.badgeChanged(.clear)
        #expect(await engine.runUntilIdle().upserted[thread] == nil)
    }

    @Test func aFailingRepliesSearchDoesNotStopTheMentionSweep() async {
        let slack = FakeSlack()
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-10))
        slack.post("C1", slackMessage(parent, user: "U2", text: "incident", replyCount: 1, latestReply: ts(-100)))
        slack.reply("C1", thread: parent, slackMessage(ts(-100), user: "U3", text: "<@U1> can you approve?"))
        slack.setSearch("<@U1>", [("C1", ts(-100), parent)])
        let engine = makeEngine(slack, clock)
        slack.failSearch("from:<@U1>", with: SlackError.api("invalid_query"))
        #expect(await engine.runUntilIdle().upserted[thread] != nil)
    }

    @Test func threadsInExcludedChannelsAreDropped() async {
        let engine = makeEngine(slackWithAThread(lastRead: ts(-3500)), clock)
        _ = await engine.runUntilIdle()
        _ = await engine.setExcluded(["C1"])
        await engine.refreshNow()
        _ = await engine.runUntilIdle()
        #expect(await engine.memory.threads.watches.isEmpty)
    }

    @Test func replyingFromSplarkClearsTheThreadOnItsNextCheck() async {
        let slack = slackWithAThread(lastRead: ts(-3500))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        await engine.didReply(channelId: "C1", threadTs: parent, ts: ts(0))
        clock.advance(61)
        #expect(await engine.runUntilIdle().removed.contains(thread))
    }

    @Test func replyingInAChannelThreadStartsWatchingIt() async {
        let engine = makeEngine(FakeSlack(), clock)
        await engine.didReply(channelId: "C1", threadTs: ts(-500), ts: ts(0))
        #expect(await engine.memory.threads.watch(channelId: "C1", threadTs: ts(-500))?.seenThrough == ts(0))
    }

    @Test func aBadgeChangeChecksDirectMessagesRightAway() async {
        let slack = FakeSlack()
        slack.addChannel("D1", kind: .im, user: "U2", lastRead: ts(-30 * 86400))
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-7200))   // quiet: not woken
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        clock.advance(30)
        slack.clearCalls()
        _ = await engine.badgeChanged(.count(1))
        _ = await engine.step()
        #expect(slack.calls.first == "conversations.info D1")
    }

    @Test func aClearBadgeClearsThreadsOnlyOnceTheBadgeHasBeenSeenLit() async {
        let engine = makeEngine(slackWithAThread(lastRead: ts(-3500)), clock)
        _ = await engine.runUntilIdle()
        #expect(await engine.badgeChanged(.clear).isEmpty)       // badges may be off in macOS: don't trust a clear we never saw lit
        _ = await engine.badgeChanged(.count(1))
        #expect(await engine.badgeChanged(.clear).removed == [thread])
        clock.advance(61)
        #expect(await engine.runUntilIdle().upserted[thread] == nil)
    }

    @Test func withoutABadgeAThreadItemClearsAfterADay() async {
        let engine = makeEngine(slackWithAThread(lastRead: ts(-3500)), clock)
        _ = await engine.runUntilIdle()
        clock.advance(25 * 3600)
        #expect(await engine.runUntilIdle().removed.contains(thread))
    }

    @Test func evenWithABadgeThatStaysLitAThreadItemClearsAfterADay() async {
        // Unread channels can keep Slack's badge at "•" for days; threads read in Slack must still go.
        let engine = makeEngine(slackWithAThread(lastRead: ts(-3500)), clock)
        _ = await engine.runUntilIdle()
        _ = await engine.badgeChanged(.dot)
        clock.advance(25 * 3600)
        #expect(await engine.runUntilIdle().removed.contains(thread))
    }

    @Test func aThreadMarkedReadStaysClearedAfterARestart() async {
        let slack = slackWithAThread(lastRead: ts(-3500))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        #expect(await engine.markedRead(thread, through: ts(-60)).removed == [thread])
        let restarted = makeEngine(slack, clock, memory: await engine.memory)
        #expect(await restarted.runUntilIdle().upserted[thread] == nil)
    }

    @Test func refreshNowWakesTheEngine() async {
        let slack = slackWithAThread(lastRead: ts(-3500))
        let engine = makeEngine(slack, clock)
        _ = await engine.runUntilIdle()
        #expect(!(await engine.step().didWork))
        await engine.refreshNow()
        #expect(await engine.step().didWork)
    }
}
