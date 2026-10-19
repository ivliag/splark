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

/// An LLM whose first answer waits until `release()`: a summary request still out when something else happens.
final class HeldLLM: LLMClient, @unchecked Sendable {
    private let lock = NSLock()
    private var gate: CheckedContinuation<Void, Never>?
    private var held = true
    private let then: FakeLLM
    init(then: FakeLLM) { self.then = then }

    var waiting: Bool { lock.withLock { gate != nil } }

    func respond(_ request: LLMRequest) async throws -> String {
        if lock.withLock({ held }) { await withCheckedContinuation { continuation in lock.withLock { gate = continuation } } }
        return try await then.respond(request)
    }

    func release() {
        let gate = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            held = false
            defer { self.gate = nil }
            return self.gate
        }
        gate?.resume()
    }
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

    /// Reset while a summary request is out, then set up again: summaries must carry on. The old triage loop used to
    /// take the new one's wake-up when its request came back, and summaries stopped until relaunch.
    @Test func summariesCarryOnAfterAResetMadeMidRequest() async throws {
        let held = HeldLLM(then: FakeLLM.everything(.action))
        let splark = try engine(llm: held)
        splark.start()
        #expect(await eventually { held.waiting })
        try await splark.reset()
        splark.start()
        held.release()
        try await Task.sleep(for: .milliseconds(200))   // the old request comes back and its loop goes to sleep
        try await splark.connect(SlackConnection(workspace: lumen, credentials: credentials))
        #expect(await eventually { splark.inbox.items.count == 3 && splark.inbox.items.allSatisfy(\.byAI) })
        await splark.stop()
    }

    /// A channel excluded before Remove (or Reset) comes back when the workspace is connected again.
    @Test func exclusionsGoWithTheWorkspace() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { splark.inbox.items.count == 3 })
        await splark.setExcluded(["C1"], teamId: "T1")
        #expect(await eventually { splark.inbox.items.count == 1 })
        try await splark.disconnect(teamId: "T1")
        try await splark.connect(SlackConnection(workspace: lumen, credentials: credentials))
        #expect(splark.excludedChannels(teamId: "T1").isEmpty)
        #expect(await eventually { splark.inbox.items.count == 3 })
        await splark.stop()
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

/// A Keychain that won't delete: locked, or refusing an app whose signature changed.
final class StubbornSecrets: SecretStore, @unchecked Sendable {
    let inner: InMemorySecretStore
    init(_ inner: InMemorySecretStore) { self.inner = inner }
    func read(_ key: String) throws -> String? { try inner.read(key) }
    func write(_ value: String, for key: String) throws { try inner.write(value, for: key) }
    func delete(_ key: String) throws { throw SecretStoreError.keychain(errSecAuthFailed) }
}

@MainActor @Suite struct SplarkEngineForTheUITests {
    let clock = ManualClock()
    let slack = FakeSlack()
    let secrets = InMemorySecretStore()
    let stateStore = StateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("splark-\(UUID().uuidString)/state.json"))
    let credentials = SlackCredentials(teamId: "T1", userId: "U1", accessToken: "xoxe.xoxp-not-a-real-token", refreshToken: "r", expiresAt: nil, clientId: "1.2")
    let lumenWithPort = Workspace(teamId: "T1", name: "Lumen", userId: "U1", userName: "ivan", url: "https://lumen.slack.com/", redirectPort: 53682, appId: "A9")

    init() {
        slack.addChannel("C1", kind: .publicChannel, name: "eng")
        slack.addChannel("G1", kind: .privateChannel, name: "leads")
        slack.addChannel("D1", kind: .im, user: "U2")
    }

    func engine(llm: LLMClient? = FakeLLM.everything(.fyi), workspace: Workspace? = nil, signedIn: ChatGPTCredentials? = nil,
                stubborn: Bool = false) throws -> SplarkEngine {
        var state = SavedState()
        state.workspaces = [workspace ?? lumenWithPort]
        try stateStore.save(state)
        try credentials.save(to: secrets)
        if let signedIn { try secrets.write(String(decoding: try JSONEncoder().encode(signedIn), as: UTF8.self), for: ChatGPTAuth.secretKey) }
        let slack = self.slack, clock = self.clock
        let secrets: SecretStore = stubborn ? StubbornSecrets(self.secrets) : self.secrets
        return SplarkEngine(environment: EngineEnvironment(
            secrets: secrets, state: stateStore, slack: { _ in slack }, chatGPT: ChatGPTSession(store: secrets, now: { clock.now }), llm: llm,
            badges: nil, sync: SyncEngine.Config(), triage: Triage.Config(), now: { clock.now }, open: { _ in true }))
    }

    @Test func listsAWorkspacesChannelsForTheExclusionsPicker() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { await splark.channels(teamId: "T1").count == 2 })
        #expect(await splark.channels(teamId: "T1") == [
            ChannelOption(id: "C1", title: "#eng", isPrivate: false),
            ChannelOption(id: "G1", title: "#leads", isPrivate: true),
        ])
        await splark.setExcluded(["C1"], teamId: "T1")
        #expect(await splark.channels(teamId: "T1").map(\.id) == ["C1", "G1"])   // excluded channels stay listed
        #expect(splark.excludedChannels(teamId: "T1") == ["C1"])
        await splark.stop()
    }

    @Test func remembersTheRegistrationToReconnectAWorkspace() throws {
        let splark = try engine()
        #expect(splark.registration(for: "T1") == SlackAppRegistration(appId: "A9", clientId: "1.2", redirectPort: 53682))
        let pasted = try engine(workspace: lumen)                                  // a pasted token has no app to re-authorise
        #expect(pasted.registration(for: "T1") == nil)
    }

    /// "Mute #eng" in the panel: the channel joins the excluded ones (Settings lists it), and Undo takes it back out.
    @Test func mutingAChannelExcludesIt() async throws {
        let splark = try engine()
        await splark.setExcluded(["G1"], teamId: "T1")
        await splark.mute(channel: "C1", teamId: "T1")
        #expect(splark.excludedChannels(teamId: "T1") == ["G1", "C1"])
        await splark.unmute(channel: "C1", teamId: "T1")
        #expect(splark.excludedChannels(teamId: "T1") == ["G1"])
    }

    @Test func pendingAppsCanBeRemoved() async throws {
        let splark = try engine()
        let app = SlackAppRegistration(appId: "A7", clientId: "7.7", redirectPort: 53683)
        await splark.addPendingApp(app)
        #expect(splark.pendingApps == [app])
        await splark.removePendingApp(app)
        #expect(splark.pendingApps.isEmpty && stateStore.load().pendingApps.isEmpty)
    }

    @Test func showsTheChatGPTAccountAndForgetsItOnSignOut() async throws {
        let start = clock.now
        let creds = ChatGPTCredentials(clientId: "oaiapp_1", hostId: "urn:uuid:0", accessToken: "a", refreshToken: "r", idToken: nil,
                                       expiresAt: start.addingTimeInterval(3600), scopes: ["chatgpt.tokens.use.direct"], email: "ivan@lumen.dev", subject: "s")
        let splark = try engine(llm: nil, signedIn: creds)
        #expect(await splark.chatGPTAccount() == ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true))
        try await splark.signOutOfChatGPT()
        #expect(await splark.chatGPTAccount() == nil)
        #expect(splark.triageState == .paused(.signedOut))
    }

    @Test func knowsWhetherSlacksBadgeCanBeRead() async throws {
        let splark = try engine()
        #expect(splark.badge == nil)
        await splark.badgeChanged(.dot)
        #expect(splark.badge == .dot)
    }

    @Test func resetForgetsEverything() async throws {
        let splark = try engine()
        splark.start()
        #expect(await eventually { !splark.inbox.items.isEmpty || splark.syncStatus["T1"]?.progress.isComplete == true })
        try await splark.reset()
        #expect(splark.workspaces.isEmpty && splark.inbox.items.isEmpty && !splark.isRunning)
        #expect(try secrets.read("slack.T1") == nil)
        #expect(!FileManager.default.fileExists(atPath: stateStore.url.path))
    }

    /// A Keychain item that won't go doesn't leave Splark half reset: everything else is forgotten, and the error says why.
    @Test func resetCarriesOnPastAKeychainItemThatWontGo() async throws {
        let splark = try engine(stubborn: true)
        splark.start()
        await #expect(throws: SecretStoreError.keychain(errSecAuthFailed)) { try await splark.reset() }
        #expect(splark.workspaces.isEmpty && splark.inbox.items.isEmpty && !splark.isRunning)
        #expect(!FileManager.default.fileExists(atPath: stateStore.url.path))
    }

    @Test func removingAWorkspaceWhoseTokenWontGoStillRemovesIt() async throws {
        let splark = try engine(stubborn: true)
        splark.start()
        await #expect(throws: SecretStoreError.keychain(errSecAuthFailed)) { try await splark.disconnect(teamId: "T1") }
        #expect(splark.workspaces.isEmpty && stateStore.load().workspaces.isEmpty)
        await splark.stop()
    }
}
