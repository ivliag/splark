import Foundation
import Testing
@testable import SplarkKit
@testable import SplarkUI

/// Stands in for the engine, Slack's Allow, ChatGPT, login items and the browser.
@MainActor final class FakeSettingsServices: SettingsServices {
    var log: [String] = []
    var workspaces: [Workspace] = [lumen, community]
    var pendingApps = [SlackAppRegistration(appId: "A7", clientId: "7.7", redirectPort: 53684)]
    var syncStatus: [String: SyncStatus] = [:]
    var badge: SlackBadge? = .dot
    var settings = SavedState.Settings()
    var account: ChatGPTAccount? = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)
    var excluded: [String: Set<String>] = ["T1": ["C2"]]
    var reconnectError: Error?, loginError: Error?, removeError: Error?, resetError: Error?
    var pastedTeam = "T2"
    var reconnectGate: CheckedContinuation<Void, Never>?
    var holdReconnect = false
    var holdUntilCancelled = false
    var holdSignIn = false

    func channels(teamId: String) async -> [ChannelOption] {
        [ChannelOption(id: "C1", title: "#eng", isPrivate: false), ChannelOption(id: "C2", title: "#random", isPrivate: false),
         ChannelOption(id: "G1", title: "#leads", isPrivate: true)]
    }
    func excludedChannels(teamId: String) -> Set<String> { excluded[teamId] ?? [] }
    func setExcluded(_ channels: Set<String>, teamId: String) async { log.append("exclude \(teamId) \(channels.sorted())") }
    func reconnect(teamId: String) async throws {
        log.append("reconnect \(teamId)")
        if holdReconnect { await withCheckedContinuation { reconnectGate = $0 } }
        if holdUntilCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch {
                log.append("reconnect cancelled")
                throw error
            }
        }
        if let reconnectError { throw reconnectError }
    }
    func finishConnecting(_ app: SlackAppRegistration) async throws { log.append("finish \(app.clientId)") }
    func connect(userToken: String) async throws -> SlackConnection {
        log.append("paste \(userToken)")
        let workspace = workspaces.first { $0.teamId == pastedTeam }
            ?? Workspace(teamId: pastedTeam, name: "Elsewhere", userId: "U5", userName: nil, url: nil, redirectPort: nil, appId: nil)
        return SlackConnection(workspace: workspace, credentials: SlackCredentials(teamId: pastedTeam, userId: "U5", accessToken: "xoxp-not-a-real-token",
                                                                                   refreshToken: nil, expiresAt: nil, clientId: nil))
    }
    func added(_ connection: SlackConnection) async throws { log.append("added \(connection.workspace.teamId)") }
    func remove(teamId: String) async throws {
        log.append("remove \(teamId)")
        if let removeError { throw removeError }
    }
    func removePending(_ app: SlackAppRegistration) async { log.append("remove pending \(app.clientId)") }
    func addWorkspace() { log.append("add") }
    func chatGPTAccount() async -> ChatGPTAccount? { account }
    func models() async -> [String] { ["gpt-5.6-luna", "gpt-6-luna"] }
    func setModel(_ model: String?) async {
        log.append("model \(model ?? "default")")
        settings.model = model
    }
    func signInToChatGPT() async throws {
        log.append("sign in")
        if holdSignIn {
            do { try await Task.sleep(for: .seconds(2)) } catch {
                log.append("sign in cancelled")
                throw error
            }
        }
        account = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)
    }
    func signOutOfChatGPT() async throws { log.append("sign out"); account = nil }
    func setSummariesPaused(_ paused: Bool) async {
        log.append("pause \(paused)")
        settings.summariesPaused = paused
    }
    func setOpenAtLogin(_ on: Bool) throws {
        if let loginError { throw loginError }
        log.append("login \(on)")
        settings.openAtLogin = on
    }
    func setShowCount(_ on: Bool) async {
        log.append("count \(on)")
        settings.showCount = on
    }
    func reset() async throws {
        log.append("reset")
        if let resetError { throw resetError }
    }
    func open(_ url: URL) { log.append("open \(url.absoluteString)") }
}

@MainActor @Suite struct SettingsModelTests {
    let services = FakeSettingsServices()
    func model() -> SettingsModel { SettingsModel(services: services, now: { now }) }

    /// Ivan's order from the live run. Settings opens on General.
    @Test func theTabsAreAboutGeneralSlackOpenAI() {
        #expect(SettingsModel.Section.allCases.map(\.rawValue) == ["About", "General", "Slack", "OpenAI"])
        #expect(model().section == .general)
    }

    @Test func listsWorkspacesWithTheirStatusAndPendingOnes() {
        var synced = SyncStatus()
        synced.lastSuccess = ago(120)
        services.syncStatus = ["T1": synced, "T2": SyncStatus(problem: .reauthorize)]
        let rows = model().workspaceRows
        #expect(rows.map(\.name) == ["Lumen", "Lumen Community", "Slack workspace"])
        #expect(rows.map(\.status) == [WorkspaceStatusText(title: "Connected", detail: "Synced 2m ago"),
                                        WorkspaceStatusText(title: "Token expired", detail: "Not synced yet"),
                                        WorkspaceStatusText(title: "Waiting for approval", detail: "An admin needs to approve it")])
        #expect(rows.map(\.action) == [nil, .pasteNewToken, .finishConnecting])
        #expect(rows.compactMap(\.action?.title) == ["Paste new token", "Finish connecting"])
        #expect(rows.map(\.canExcludeChannels) == [true, true, false])
    }

    @Test(arguments: [
        (SyncProblem.tokenRevoked, false, "T1", WorkspaceRow.Action.reconnect),
        (.tokenRevoked, false, "T2", .pasteNewToken),     // a pasted token has no app to Allow again
        (.reauthorize, false, "T1", .reconnect),
        (.offline(retryAt: now), false, "T1", nil),
        (nil, true, "T1", .reconnect),                     // "Needs new permissions"
    ] as [(SyncProblem?, Bool, String, WorkspaceRow.Action?)])
    func theRowsActionFollowsItsProblem(problem: SyncProblem?, missingScope: Bool, team: String, action: WorkspaceRow.Action?) {
        services.syncStatus = [team: SyncStatus(problem: problem, missingScope: missingScope)]
        #expect(model().workspaceRows.first { $0.id == team }?.action == action)
    }

    @Test func saysWhetherSlacksBadgeCanBeRead() {
        #expect(model().badgeLine == "Slack is open, so new messages show up within seconds.")
        services.badge = nil
        #expect(model().badgeLine == "Slack isn't open, or its Dock badge can't be read, so Splark checks every couple of minutes.")
    }

    @Test func reconnectWaitsForAllowAndSaysWhyItFailed() async throws {
        services.holdReconnect = true
        let m = model()
        let reconnecting = Task { await m.perform(.reconnect, on: m.workspaceRows[0]) }
        try #require(await eventually { services.reconnectGate != nil })
        #expect(m.working == "T1")
        services.reconnectError = WorkspaceSetupError.cancelled
        services.reconnectGate?.resume()
        await reconnecting.value
        #expect(m.working == nil)
        #expect(m.message == "Slack sign-in was cancelled. Click Try again when you're ready.")
        services.holdReconnect = false
        services.reconnectError = nil
        await m.perform(.finishConnecting, on: m.workspaceRows[2])
        #expect(services.log == ["reconnect T1", "finish 7.7"] && m.message == nil)
    }

    @Test func cancellingStopsWaitingForAllowWithoutComplaint() async {
        services.holdUntilCancelled = true
        let m = model()
        let reconnecting = Task { await m.perform(.reconnect, on: m.workspaceRows[0]) }
        #expect(await eventually { services.log == ["reconnect T1"] })
        #expect(m.working == "T1")
        m.cancel()
        await reconnecting.value
        #expect(services.log == ["reconnect T1", "reconnect cancelled"])
        #expect(m.working == nil && m.message == nil)
    }

    /// Both apps would want the same redirect port: one Allow at a time.
    @Test func aSecondReconnectWaitsItsTurn() async {
        services.holdUntilCancelled = true
        let m = model()
        let first = Task { await m.perform(.reconnect, on: m.workspaceRows[0]) }
        #expect(await eventually { services.log == ["reconnect T1"] })
        await m.perform(.finishConnecting, on: m.workspaceRows[2])
        #expect(services.log == ["reconnect T1"] && m.working == "T1")
        m.cancel()
        await first.value
    }

    @Test func aChatGPTSignInCanBeCancelled() async throws {
        services.holdSignIn = true
        let m = model()
        let signingIn = Task { await m.signIn() }
        try #require(await eventually { services.log.last == "sign in" })
        m.cancel()
        await signingIn.value
        #expect(services.log.last == "sign in cancelled" && !m.signingIn && m.message == nil)
    }

    @Test func aSignInSplarkCantReadSaysWhatToDo() async {
        services.reconnectError = ReconnectError.noSavedSignIn
        let m = model()
        await m.perform(.reconnect, on: m.workspaceRows[0])
        #expect(m.message == "Splark can't read Lumen's saved sign-in from the Keychain. Remove it and add it again.")
    }

    /// Paused from the menu while Settings is open: the switch shows it.
    @Test func theSwitchesShowWhatTheEngineHasNow() {
        let m = model()
        services.settings.summariesPaused = true
        services.settings.showCount = false
        #expect(m.summariesPaused && !m.showCount)
    }

    @Test func aPastedTokenReplacesTheWorkspacesOwn() async {
        let m = model()
        await m.perform(.pasteNewToken, on: m.workspaceRows[1])
        #expect(m.pasting == "T2")
        m.newToken = " xoxp-new "
        await m.savePastedToken()
        #expect(services.log == ["paste xoxp-new", "added T2"])
        #expect(m.pasting == nil && m.newToken.isEmpty)
    }

    @Test func aTokenForAnotherWorkspaceIsRefused() async {
        services.pastedTeam = "T5"
        let m = model()
        await m.perform(.pasteNewToken, on: m.workspaceRows[1])
        m.newToken = "xoxp-other"
        await m.savePastedToken()
        #expect(services.log == ["paste xoxp-other"])
        #expect(m.message == "That token is for Elsewhere, not Lumen Community. Paste one made in Lumen Community.")
        #expect(m.pasting == "T2" && m.newToken == "xoxp-other")
    }

    @Test func removingAWorkspaceAsksFirst() async {
        let m = model()
        m.askToRemove(m.workspaceRows[0])
        #expect(m.removal?.name == "Lumen")
        #expect(m.removalNote == "Splark forgets Lumen's token. To delete your private Splark app too, open api.slack.com/apps, choose Splark, and click Delete App.")
        m.cancelRemoval()
        #expect(m.removal == nil && services.log.isEmpty)
        m.askToRemove(m.workspaceRows[0])
        await m.confirmRemoval()
        #expect(services.log == ["remove T1"] && m.removal == nil)
        m.askToRemove(m.workspaceRows[2])
        #expect(m.removalNote == "Splark forgets this app. To delete it from Slack too, open api.slack.com/apps, choose Splark, and click Delete App.")
        await m.confirmRemoval()
        #expect(services.log.last == "remove pending 7.7")
    }

    @Test func pickingExcludedChannels() async {
        let m = model()
        await m.editChannels(m.workspaceRows[0])
        #expect(m.channelPicker?.name == "Lumen")
        #expect(m.channelPicker?.shown.map(\.title) == ["#eng", "#random", "#leads"])
        #expect(m.channelPicker?.excluded == ["C2"])
        m.channelPicker?.search = "RA"
        #expect(m.channelPicker?.shown.map(\.title) == ["#random"])
        m.toggleChannel("C1")
        m.toggleChannel("C2")
        await m.saveChannels()
        #expect(services.log == ["exclude T1 [\"C1\"]"] && m.channelPicker == nil)
    }

    @Test func chatGPTAccountAndModel() async {
        services.settings.model = "gpt-5.6-luna"
        let m = model()
        await m.load()
        #expect(m.account?.email == "ivan@lumen.dev")
        #expect(m.models == ["gpt-5.6-luna", "gpt-6-luna"] && m.recommendedModel == "gpt-6-luna")
        #expect(m.model == "gpt-5.6-luna")
        await m.chooseModel(nil)
        #expect(m.model == nil)
        await m.signOut()
        #expect(m.account == nil && m.models.isEmpty)
        await m.signIn()
        #expect(m.account?.email == "ivan@lumen.dev" && m.models.count == 2)
        #expect(services.log == ["model default", "sign out", "sign in"])
    }

    @Test func generalSwitches() async {
        let m = model()
        #expect(m.openAtLogin && m.showCount && !m.summariesPaused)
        m.setOpenAtLogin(false)
        await m.setShowCount(false)
        await m.setSummariesPaused(true)
        #expect(services.log == ["login false", "count false", "pause true"])
        #expect(!m.openAtLogin && !m.showCount && m.summariesPaused)
    }

    @Test func openAtLoginExplainsWhenMacOSRefuses() {
        services.loginError = CocoaError(.featureUnsupported)
        let m = model()
        m.setOpenAtLogin(false)
        #expect(m.openAtLogin)
        #expect(m.message == "macOS didn't let Splark change this. Check System Settings → General → Login Items.")
    }

    @Test func resetAsksFirst() async {
        var reset = false
        let m = SettingsModel(services: services, now: { now }, onReset: { reset = true })
        m.askToReset()
        #expect(m.confirmingReset)
        await m.confirmReset()
        #expect(services.log == ["reset"] && reset && !m.confirmingReset)
    }

    /// The engine forgets everything it can even when a Keychain item won't go, so setup starts again regardless.
    @Test func aResetThatHitsAKeychainErrorStillStartsOver() async {
        services.resetError = SecretStoreError.keychain(-25293)
        var reset = false
        let m = SettingsModel(services: services, now: { now }, onReset: { reset = true })
        m.askToReset()
        await m.confirmReset()
        #expect(reset)
    }

    @Test func aRemovedWorkspaceWhoseTokenWontGoSaysSo() async {
        services.removeError = SecretStoreError.keychain(-25293)
        let m = model()
        m.askToRemove(m.workspaceRows[0])
        await m.confirmRemoval()
        #expect(m.message == "Removed Lumen, but macOS wouldn't delete its token from the Keychain.")
    }

    @Test func addingAWorkspaceAndTheAboutLinks() {
        let m = model()
        m.addWorkspace()
        #expect(m.version == "Version \(SplarkInfo.version) · Open source, MIT licence")
        m.openRepository()
        m.openDoll()
        #expect(services.log == ["add", "open https://github.com/ivliag/splark", "open https://github.com/xiaogdgenuine/Doll"])
    }
}
