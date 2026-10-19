import Foundation
import Testing
@testable import SplarkKit
@testable import SplarkUI

/// Stands in for WorkspaceSetup, the engine and ChatGPT; each call can be told to fail or to wait.
@MainActor final class FakeSetupServices: SetupServices {
    var log: [String] = []
    var createError: Error?, authorizeError: Error?, signInError: Error?
    var account = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)
    var authorizeGate: CheckedContinuation<Void, Never>?
    var holdAuthorize = false
    var holdUntilCancelled = false   // like the real Allow: waits on the redirect port until cancelled
    let app = SlackAppRegistration(appId: "A9", clientId: "1.2", redirectPort: 53682)

    func connection(_ name: String, team: String) -> SlackConnection {
        SlackConnection(workspace: Workspace(teamId: team, name: name, userId: "U1", userName: "ivan", url: "https://\(name.lowercased()).slack.com/",
                                             redirectPort: 53682, appId: "A9"),
                        credentials: SlackCredentials(teamId: team, userId: "U1", accessToken: "xoxe.xoxp-not-a-real-token", refreshToken: nil, expiresAt: nil, clientId: "1.2"))
    }

    func createApp(configToken: String) async throws -> SlackAppRegistration {
        log.append("create \(configToken)")
        if let createError { throw createError }
        return app
    }
    func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection {
        log.append("authorize \(app.clientId)")
        if holdAuthorize { await withCheckedContinuation { authorizeGate = $0 } }
        if holdUntilCancelled {
            do { try await Task.sleep(for: .seconds(2)) } catch {
                log.append("authorize cancelled")
                throw error
            }
        }
        if let authorizeError { throw authorizeError }
        return connection("Lumen", team: "T1")
    }
    func connect(userToken: String) async throws -> SlackConnection {
        log.append("paste \(userToken)")
        return connection("Lumen Community", team: "T2")
    }
    func added(_ connection: SlackConnection) async throws { log.append("added \(connection.workspace.teamId)") }
    func waitingForApproval(_ app: SlackAppRegistration) async { log.append("pending \(app.clientId)") }
    func signInToChatGPT() async throws -> ChatGPTAccount {
        log.append("chatgpt")
        if let signInError { throw signInError }
        return account
    }
    func open(_ url: URL) { log.append("open \(url.host ?? url.absoluteString)") }
    func setOpenAtLogin(_ on: Bool) { log.append("login \(on)") }
    func setShowCount(_ on: Bool) { log.append("count \(on)") }
    func finish() { log.append("finish") }
}

@MainActor @Suite struct SetupModelTests {
    let services = FakeSetupServices()
    func model() -> SetupModel { SetupModel(services: services) }

    @Test func walksThroughTheFourSteps() {
        let m = model()
        #expect(m.step == .welcome)
        m.next()
        #expect(m.step == .slack && !m.canContinue)
        m.back()
        #expect(m.step == .welcome)
    }

    @Test func connectingCreatesTheAppWaitsForAllowAndForgetsTheToken() async {
        let m = model()
        m.step = .slack
        m.token = "  xoxe.xoxp-config  "
        #expect(m.canConnect)
        await m.connect()
        #expect(services.log == ["create xoxe.xoxp-config", "authorize 1.2", "added T1"])
        #expect(m.slack == .connected && m.token.isEmpty)
        #expect(m.connected.map(\.name) == ["Lumen"] && m.canContinue)
    }

    @Test func showsWaitingForAllowWhileTheBrowserIsOpen() async throws {
        services.holdAuthorize = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.authorizeGate != nil })
        #expect(m.slack == .waitingForAllow)
        services.authorizeGate?.resume()
        await connecting.value
        #expect(m.slack == .connected)
    }

    @Test(arguments: [
        (WorkspaceSetupError.tokenRejected("token_expired") as Error,
         "That token didn't work. Setup tokens expire after 12 hours and are tied to one workspace. Generate a fresh one and paste it again."),
        (WorkspaceSetupError.noFreePort, "Splark's sign-in ports (53682–53691) are all in use. Quit the app using them and try again."),
    ])
    func aFailedConnectSaysWhyAndKeepsTheField(error: Error, message: String) async {
        services.createError = error
        let m = model()
        m.token = "xoxe.xoxp-config"
        await m.connect()
        #expect(m.slack == .failed(message))
        #expect(m.token == "xoxe.xoxp-config")   // kept, so it can be corrected
    }

    @Test(arguments: [
        (WorkspaceSetupError.cancelled as Error, "Slack sign-in was cancelled. Click Try again when you're ready."),
        (WorkspaceSetupError.timedOut, "Slack didn't answer in time. Click Try again."),
        (WorkspaceSetupError.portBusy(53682), "Another app is using port 53682, which your Splark app needs. Quit it and click Try again."),
    ])
    func aFailedAllowCanBeRetriedWithoutANewToken(error: Error, message: String) async {
        services.authorizeError = error
        let m = model()
        m.token = "xoxe.xoxp-config"
        await m.connect()
        #expect(m.slack == .allowFailed(message))
        services.authorizeError = nil
        await m.retryAllow()
        #expect(services.log.filter { $0.hasPrefix("create") }.count == 1)   // the same app, Allow again
        #expect(m.slack == .connected)
    }

    @Test func aWorkspaceNeedingApprovalLetsSetupGoOn() async throws {
        services.holdAuthorize = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.authorizeGate != nil })
        await m.needsApproval()
        #expect(m.slack == .waitingForApproval && m.canContinue)
        #expect(services.log.last == "pending 1.2")
        services.authorizeGate?.resume()
        await connecting.value
        #expect(m.slack == .waitingForApproval)    // the abandoned Allow doesn't come back to haunt
    }

    /// Allow listens on the app's redirect port. Leaving it waiting would keep the port, so the next Allow on it would fail.
    @Test func cancellingStopsWaitingForAllow() async {
        services.holdUntilCancelled = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.log.last == "authorize 1.2" })
        m.cancel()
        await connecting.value
        #expect(services.log.last == "authorize cancelled")
        #expect(m.slack == .allowFailed("Slack sign-in was cancelled. Click Try again when you're ready."))
    }

    @Test func needingApprovalStopsWaitingForAllowToo() async {
        services.holdUntilCancelled = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.log.last == "authorize 1.2" })
        await m.needsApproval()
        await connecting.value
        #expect(services.log.contains("authorize cancelled") && m.slack == .waitingForApproval)
    }

    /// While one workspace waits for an admin, the next can be connected straight away, as in the prototype.
    @Test func anotherWorkspaceCanBeConnectedWhileOneWaitsForApproval() async throws {
        services.holdAuthorize = true
        let m = model()
        m.token = "xoxe.xoxp-config"
        let connecting = Task { await m.connect() }
        #expect(await eventually { services.authorizeGate != nil })
        await m.needsApproval()
        services.authorizeGate?.resume()
        await connecting.value
        m.token = "xoxe.xoxp-second"
        #expect(m.canConnect)
    }

    @Test func doneSaysWhatHappensNext() async {
        let m = model()
        #expect(m.doneMessage == "Splark is in your menu bar now. It starts catching up once your workspace is approved.\nClick the spark to see what needs you.")
        m.token = "xoxe.xoxp-config"
        await m.connect()
        #expect(m.doneMessage == "Splark is in your menu bar now and is catching up on 1 workspace.\nClick the spark to see what needs you.")
    }

    @Test func anotherWorkspaceTheSameWay() async {
        let m = model()
        m.token = "a"
        await m.connect()
        m.addAnother()
        #expect(m.slack == .idle && m.connected.count == 1)
    }

    @Test func thePastedTokenFallback() async {
        let m = model()
        m.showManual()
        #expect(m.slack == .manual)
        m.openManifestLink()
        #expect(services.log.last == "open api.slack.com")
        m.manualToken = " xoxp-pasted "
        await m.connectManual()
        #expect(services.log.suffix(2) == ["paste xoxp-pasted", "added T2"])
        #expect(m.connected.map(\.name) == ["Lumen Community"] && m.manualToken.isEmpty)
    }

    @Test func signingInToChatGPT() async {
        let m = model()
        m.step = .chatgpt
        #expect(!m.canContinue)
        await m.signIn()
        #expect(m.chatgpt == .signedIn(ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)) && m.canContinue)
    }

    @Test func aPlanThatCantBeUsedStillLetsSetupFinish() async {
        services.account = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: false)
        let m = model()
        m.step = .chatgpt
        await m.signIn()
        #expect(m.chatgpt == .failed("This ChatGPT plan can't be used for summaries. Splark will still rank what's unread, without summaries."))
        #expect(m.canContinue)
    }

    @Test func aCancelledChatGPTSignInCanBeTriedAgain() async {
        services.signInError = ChatGPTAuthError.denied(error: "access_denied", description: nil)
        let m = model()
        m.step = .chatgpt
        await m.signIn()
        #expect(m.chatgpt == .failed("Sign-in was cancelled. Try again when you're ready."))
        #expect(!m.canContinue)
    }

    @Test func doneAppliesTheLastStepsSwitches() {
        let m = model()
        m.step = .done
        #expect(m.openAtLogin && m.showCount)   // both on unless changed (spec §4.4)
        m.finish()
        #expect(services.log == ["login true", "count true", "finish"])
        services.log = []
        m.openAtLogin = false
        m.showCount = false
        m.finish()
        #expect(services.log == ["login false", "count false", "finish"])
    }
}
