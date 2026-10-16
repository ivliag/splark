import Foundation
import Testing
@testable import SplarkKit

@Suite struct WorkspaceSetupTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let manifestCreated = #"{"ok":true,"app_id":"A9","credentials":{"client_id":"1.2","client_secret":"s"},"oauth_authorize_url":"https://slack.com/oauth/v2/authorize?client_id=1.2"}"#
    let exchanged = #"{"ok":true,"app_id":"A9","authed_user":{"id":"U1","scope":"im:history","access_token":"xoxe.xoxp-1","token_type":"user","refresh_token":"xoxe-1-r","expires_in":43200},"team":{"id":"T1","name":"Lumen"}}"#
    let me = #"{"ok":true,"user_id":"U1","user":"ivan","team_id":"T1","team":"Lumen","url":"https://lumen.slack.com/"}"#

    /// A port nothing is listening on.
    func freePort() throws -> UInt16 {
        let probe = try LoopbackServer(port: 0, path: "/x")
        defer { probe.stop() }
        return probe.port
    }

    /// Plays the browser: follows the authorize URL's redirect with the given query.
    static func browser(_ query: @escaping @Sendable (_ state: String) -> String) -> @Sendable (URL) -> Void {
        { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let state = items.first { $0.name == "state" }?.value ?? ""
            let redirect = items.first { $0.name == "redirect_uri" }?.value ?? ""
            Task { _ = try? await URLSession.shared.data(from: URL(string: "\(redirect)?\(query(state))")!) }
        }
    }

    @Test func createAppUsesTheConfigTokenOnceWithAFreePort() async throws {
        let stub = StubTransport(json: manifestCreated)
        let port = try freePort()
        let setup = WorkspaceSetup(transport: stub, sleeper: RecordingSleeper(), ports: [port], open: { _ in })
        let app = try await setup.createApp(configToken: "xoxe.xoxp-cfg")
        #expect(app == SlackAppRegistration(appId: "A9", clientId: "1.2", redirectPort: port))
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer xoxe.xoxp-cfg")
        #expect(stub.formBody(0)["manifest"]?.contains("http://localhost:\(port)/slack/callback") == true)
    }

    @Test func skipsBusyPorts() async throws {
        let busy = try LoopbackServer(port: 0, path: "/x")
        let free = try freePort()
        let setup = WorkspaceSetup(transport: StubTransport(json: manifestCreated), sleeper: RecordingSleeper(), ports: [busy.port, free], open: { _ in })
        #expect(try await setup.createApp(configToken: "t").redirectPort == free)
        let none = WorkspaceSetup(transport: StubTransport(json: manifestCreated), sleeper: RecordingSleeper(), ports: [busy.port], open: { _ in })
        await #expect(throws: WorkspaceSetupError.noFreePort) { try await none.createApp(configToken: "t") }
        busy.stop()
    }

    @Test func aRejectedConfigTokenSaysSo() async throws {
        let setup = WorkspaceSetup(transport: StubTransport(json: #"{"ok":false,"error":"token_expired"}"#), sleeper: RecordingSleeper(),
                                   ports: [try freePort()], open: { _ in })
        await #expect(throws: WorkspaceSetupError.tokenRejected("token_expired")) { try await setup.createApp(configToken: "old") }
    }

    @Test func authorizeOpensSlackAndExchangesTheCode() async throws {
        let stub = StubTransport(json: exchanged, me)
        let port = try freePort()
        let setup = WorkspaceSetup(transport: stub, sleeper: RecordingSleeper(), now: { start },
                                   open: Self.browser { "code=c0de&state=\($0)" })
        let connection = try await setup.authorize(SlackAppRegistration(appId: "A9", clientId: "1.2", redirectPort: port))
        #expect(connection.credentials == SlackCredentials(teamId: "T1", userId: "U1", accessToken: "xoxe.xoxp-1", refreshToken: "xoxe-1-r",
                                                           expiresAt: start.addingTimeInterval(43200), clientId: "1.2"))
        #expect(connection.workspace == Workspace(teamId: "T1", name: "Lumen", userId: "U1", userName: "ivan", url: "https://lumen.slack.com/",
                                                  redirectPort: port, appId: "A9"))
        let exchange = stub.formBody(0)
        #expect(exchange["code"] == "c0de" && exchange["client_id"] == "1.2")
        #expect(exchange["redirect_uri"] == "http://localhost:\(port)/slack/callback")
        #expect(exchange["code_verifier"]?.count == 43 && exchange["client_secret"] == nil)
    }

    @Test func cancellingInSlackConnectsNothing() async throws {
        let stub = StubTransport(json: exchanged, me)
        let setup = WorkspaceSetup(transport: stub, sleeper: RecordingSleeper(), open: Self.browser { "error=access_denied&state=\($0)" })
        await #expect(throws: WorkspaceSetupError.cancelled) {
            try await setup.authorize(SlackAppRegistration(appId: nil, clientId: "1.2", redirectPort: try freePort()))
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func aBusyRedirectPortIsReported() async throws {
        let busy = try LoopbackServer(port: 0, path: "/x")
        let setup = WorkspaceSetup(transport: StubTransport([]), sleeper: RecordingSleeper(), open: { _ in })
        await #expect(throws: WorkspaceSetupError.portBusy(busy.port)) {
            try await setup.authorize(SlackAppRegistration(appId: nil, clientId: "1.2", redirectPort: busy.port))
        }
        busy.stop()
    }

    @Test func aPastedUserTokenConnectsWithoutRefresh() async throws {
        let stub = StubTransport(json: me)
        let connection = try await WorkspaceSetup(transport: stub, sleeper: RecordingSleeper(), open: { _ in }).connect(userToken: "xoxp-manual")
        #expect(connection.credentials == SlackCredentials(teamId: "T1", userId: "U1", accessToken: "xoxp-manual", refreshToken: nil, expiresAt: nil, clientId: nil))
        #expect(connection.workspace.redirectPort == nil && connection.workspace.name == "Lumen")
        let rejected = WorkspaceSetup(transport: StubTransport(json: #"{"ok":false,"error":"invalid_auth"}"#), sleeper: RecordingSleeper(), open: { _ in })
        await #expect(throws: WorkspaceSetupError.tokenRejected("invalid_auth")) { try await rejected.connect(userToken: "xoxp-bad") }
    }
}
