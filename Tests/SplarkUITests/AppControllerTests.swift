import AppKit
import Observation
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor final class FakeLoginItem: LoginItemControlling {
    var isEnabled = false
    func setEnabled(_ on: Bool) throws { isEnabled = on }
}

@MainActor @Observable final class Counter {
    var value = 0
}

@MainActor @Suite(.serialized) struct AppControllerTests {
    let stateStore = StateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("splark-\(UUID().uuidString)/state.json"))
    let secrets = InMemorySecretStore()

    /// An app over an empty, waiting or connected state. No workspace has a token, so Slack is never called (a
    /// connected one shows "Reconnect needed").
    func app(waiting: Bool = false, connected: Bool = false) throws -> AppController {
        _ = NSApplication.shared
        var state = SavedState()
        if waiting { state.pendingApps = [SlackAppRegistration(appId: "A7", clientId: "7.7", redirectPort: 53684)] }
        if connected { state.workspaces = [lumen] }
        try stateStore.save(state)
        let environment = EngineEnvironment(
            secrets: secrets, state: stateStore, slack: { _ in fatalError("no workspace runs in these tests") }, chatGPT: ChatGPTSession(store: secrets),
            llm: nil, badges: nil, sync: SyncEngine.Config(), triage: Triage.Config(), now: { now }, open: { _ in true })
        return AppController(environment: environment, loginItem: FakeLoginItem(), statusButton: NSButton())
    }

    func directMessage() -> SyncUpdate {
        var update = SyncUpdate()
        update.upsert(ConversationSnapshot(key: ItemKey(teamId: "T1", channelId: "D1"), kind: .dm, title: "Marta Ruiz",
                                           unread: [SnapshotMessage(ts: SlackTS.ts(ago(60)), authorId: "U2", author: "Marta Ruiz", text: "can you approve?", mentionsMe: false)],
                                           context: [], moreUnread: false))
        return update
    }

    @Test func aWatchSeesTheValueNowAndEveryChange() async {
        let counter = Counter()
        var seen: [Int] = []
        let watch = Watch({ counter.value }) { seen.append($0) }
        #expect(seen == [0])
        counter.value = 1
        #expect(await eventually { seen == [0, 1] })
        counter.value = 2
        #expect(await eventually { seen == [0, 1, 2] })
        watch.cancel()
        counter.value = 3
        try? await Task.sleep(for: .milliseconds(100))
        #expect(seen == [0, 1, 2])
    }

    @Test func theFirstRunOpensSetup() async throws {
        let app = try app()
        app.launch()
        #expect(app.engine.isRunning)
        #expect(app.setup?.isVisible == true && app.setupModel?.step == .welcome)
        app.setup?.close()
        #expect(app.setup == nil)
        await app.terminate()
    }

    @Test func aWorkspaceWaitingForApprovalSkipsSetup() async throws {
        let app = try app(waiting: true)
        app.launch()
        #expect(app.setup == nil)
        await app.terminate()
        #expect(!app.engine.isRunning)
    }

    @Test func theSparkFollowsTheInboxAndTheCountSwitch() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.engine.inbox.setWorkspaces([lumen])
        app.engine.inbox.apply(directMessage())
        #expect(await eventually { app.statusItem.button.title == " 1" })
        await app.engine.updateSettings { $0.showCount = false }
        #expect(await eventually { app.statusItem.button.title == "" })
        #expect(app.statusItem.button.accessibilityLabel() == "Splark: 1 needs you")
        await app.terminate()
    }

    @Test func theMenuPausesSummaries() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.setSummariesPaused(true)
        #expect(await eventually { app.engine.settings.summariesPaused && app.statusItem.summariesPaused })
        await app.terminate()
    }

    @Test func aClickOnTheSparkTogglesThePanel() async throws {
        let app = try app(connected: true)
        app.launch()
        app.togglePanel()
        #expect(app.panel.isShown)
        app.panelModel.escape()
        #expect(!app.panel.isShown)
        app.togglePanel()
        app.panelModel.startReply(item())
        app.togglePanel()
        #expect(!app.panel.isShown && app.panelModel.expanded == nil)   // reopened, it starts collapsed
        await app.terminate()
    }

    /// Nothing connected: an empty "All caught up" panel would mislead, so the spark brings setup back (live run).
    @Test func withNothingConnectedTheSparkOpensSetup() async throws {
        let app = try app()
        app.launch()
        app.setup?.close()
        app.togglePanel()
        #expect(!app.panel.isShown && app.setup?.isVisible == true)
        app.setup?.close()
        await app.terminate()
    }

    /// Only a workspace waiting for an admin: the spark opens Settings → Slack, where Finish connecting is.
    @Test func aWorkspaceWaitingForApprovalOpensSettingsAtSlack() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.togglePanel()
        #expect(!app.panel.isShown && app.settings?.isVisible == true && app.settingsModel?.section == .slack)
        app.settings?.close()
        await app.terminate()
    }

    @Test func addingAWorkspaceFromSettingsOpensSetupAtSlack() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.showSettings()
        #expect(app.settings?.isVisible == true)
        app.settingsModel?.addWorkspace()
        #expect(app.setupModel?.step == .slack && app.setupModel?.addingWorkspace == true)
        app.setup?.close()
        app.settings?.close()
        #expect(app.settings == nil)
        await app.terminate()
    }

    @Test func resettingGoesBackToSetup() async throws {
        let app = try app(waiting: true)
        app.launch()
        app.showSettings()
        await app.settingsModel?.confirmReset()
        #expect(app.settings == nil)
        #expect(app.setupModel?.step == .welcome && app.setupModel?.addingWorkspace == false)
        #expect(app.engine.isRunning && app.engine.pendingApps.isEmpty)
        app.setup?.close()
        await app.terminate()
    }

    @Test func theMainMenuGivesWindowsTheEditingShortcuts() {
        let items = AppController.mainMenu().items.flatMap { $0.submenu?.items ?? [] }
        let expected: [(String, Selector)] = [
            ("x", #selector(NSText.cut(_:))), ("c", #selector(NSText.copy(_:))), ("v", #selector(NSText.paste(_:))),
            ("a", #selector(NSText.selectAll(_:))), ("z", Selector(("undo:"))), ("w", #selector(NSWindow.performClose(_:))),
        ]
        for (key, action) in expected {
            #expect(items.contains { $0.keyEquivalent == key && $0.action == action }, "⌘\(key)")
        }
    }

    /// The panel takes the keyboard while another app stays frontmost, so ⌘Q meant for that app would quit Splark
    /// (it did, in the live run). Quit is in the spark's menu instead.
    @Test func commandQIsLeftToTheFrontmostApp() {
        let items = AppController.mainMenu().items.flatMap { $0.submenu?.items ?? [] }
        #expect(!items.contains { $0.keyEquivalent == "q" })
        #expect(!items.contains { $0.action == #selector(NSApplication.terminate(_:)) })
    }
}
