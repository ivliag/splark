import Foundation
import Testing
@testable import SplarkKit

/// Waits for `condition`, polling, for up to `timeout` of real time.
@MainActor func eventually(_ timeout: Duration = .seconds(3), _ condition: @MainActor () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

@MainActor @Suite struct SplarkEngineTests {
    let clock = ManualClock()
    let slack = FakeSlack()
    let secrets = InMemorySecretStore()
    let stateStore = StateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("splark-\(UUID().uuidString)/state.json"))
    let credentials = SlackCredentials(teamId: "T1", userId: "U1", accessToken: "xoxe.xoxp-1", refreshToken: "r", expiresAt: nil, clientId: "1.2")

    init() throws {
        slack.addUser("U2", "Marta Ruiz")
        slack.addChannel("D1", kind: .im, user: "U2", lastRead: ts(-1000))
        slack.post("D1", slackMessage(ts(-600), user: "U2", text: "can you approve?"))
        slack.addChannel("C1", kind: .publicChannel, name: "eng", lastRead: ts(-4000))
        slack.post("C1", slackMessage(ts(-3000), user: "U2", text: "release plan?", replyCount: 1, latestReply: ts(-60), replyUsers: ["U1"]))
        slack.reply("C1", thread: ts(-3000), slackMessage(ts(-2000), user: "U1", text: "draft", threadTs: ts(-3000)))
        slack.reply("C1", thread: ts(-3000), slackMessage(ts(-60), user: "U2", text: "done?", threadTs: ts(-3000)))
    }

    func engine(llm: LLMClient = FakeLLM.everything(.action), workspaces: [Workspace] = [lumen], withToken: Bool = true) throws -> SplarkEngine {
        var state = SavedState()
        state.workspaces = workspaces
        try stateStore.save(state)
        if withToken { try credentials.save(to: secrets) }
        var triage = Triage.Config()
        triage.quiet = 0
        triage.maxWait = 0
        let slack = self.slack
        let clock = self.clock
        return SplarkEngine(environment: EngineEnvironment(
            secrets: secrets, state: stateStore, slack: { _ in slack }, chatGPT: ChatGPTSession(store: secrets), llm: llm,
            badges: nil, sync: SyncEngine.Config(), triage: triage, now: { clock.now }, open: { _ in true }))
    }

    @Test func catchesUpAndSummarises() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { splark.inbox.items.count == 3 && splark.inbox.items.allSatisfy(\.byAI) })
        #expect(splark.inbox.summary.headline == "3 need you" && splark.inbox.summary.spark == .bright)
        #expect(await eventually { splark.syncStatus["T1"]?.progress.isComplete == true })
        await splark.stop()
    }

    @Test func stoppingSavesWhatSyncLearned() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { splark.inbox.items.count == 3 })
        await splark.stop()
        let saved = stateStore.load()
        #expect(saved.sync["T1"]?.threads.watch(channelId: "C1", threadTs: ts(-3000)) != nil)
        #expect(saved.userNames["T1"]?["U2"]?.name == "Marta Ruiz")
    }

    @Test func connectingAndDisconnectingAWorkspace() async throws {
        let splark = try engine(workspaces: [], withToken: false)
        splark.start()
        try await splark.connect(SlackConnection(workspace: lumen, credentials: credentials))
        #expect(await eventually { splark.inbox.items.count == 3 })
        #expect(try SlackCredentials.load(teamId: "T1", from: secrets) == credentials)
        #expect(stateStore.load().workspaces == [lumen])
        try await splark.disconnect(teamId: "T1")
        #expect(splark.inbox.items.isEmpty)
        #expect(try secrets.read("slack.T1") == nil)
        #expect(stateStore.load().workspaces.isEmpty)
        await splark.stop()
    }

    @Test func aWorkspaceWithoutItsTokenAsksToReconnect() async throws {
        let splark = try engine(withToken: false)
        splark.start()
        #expect(splark.syncStatus["T1"]?.problem == .reauthorize)
        await splark.stop()
    }

    @Test func markReadFromThePanelReachesSlack() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { splark.inbox.items.count == 3 })
        let dm = try #require(splark.inbox.items.first { $0.key.channelId == "D1" })
        splark.actions.markRead([dm])
        await splark.actions.commitPendingReads()
        #expect(slack.lastRead("D1") == ts(-600))
        #expect(!splark.inbox.items.contains { $0.key.channelId == "D1" })
        await splark.stop()
    }

    @Test func pausedSummariesLeaveTheHeuristic() async throws {
        let llm = FakeLLM.everything(.action)
        let splark = try engine(llm: llm)
        await splark.setSummariesPaused(true)
        splark.start()
        #expect(await eventually { splark.inbox.items.count == 3 })
        #expect(await eventually { splark.triageState == .paused(.byUser) })
        #expect(splark.inbox.items.allSatisfy { !$0.byAI } && llm.requests.isEmpty)
        #expect(stateStore.load().settings.summariesPaused)
        await splark.stop()
    }

    @Test func aBadgeChangeChecksDirectMessagesAtOnce() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { splark.inbox.items.count == 3 })
        slack.post("D1", slackMessage(ts(-5), user: "U2", text: "ping"))
        await splark.badgeChanged(.count(1))
        #expect(await eventually { splark.inbox.items.first { $0.key.channelId == "D1" }?.newestTs == ts(-5) })
        await splark.stop()
    }
}
