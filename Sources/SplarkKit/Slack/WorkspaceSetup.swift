import Foundation

/// A connected Slack workspace, as kept in state.json (no secrets; spec §8).
public struct Workspace: Codable, Sendable, Equatable, Identifiable {
    public var id: String { teamId }
    public let teamId: String
    public var name: String
    public var userId: String
    public var userName: String?
    public var url: String?             // e.g. "https://lumen.slack.com/", for permalinks
    public var redirectPort: UInt16?    // the private app's redirect port; nil for pasted tokens
    public var appId: String?

    public init(teamId: String, name: String, userId: String, userName: String?, url: String?, redirectPort: UInt16?, appId: String?) {
        self.teamId = teamId
        self.name = name
        self.userId = userId
        self.userName = userName
        self.url = url
        self.redirectPort = redirectPort
        self.appId = appId
    }
}

/// The user's private Slack app, before (or between) authorisations: enough to rerun "Allow" without a new config token.
public struct SlackAppRegistration: Codable, Sendable, Equatable {
    public let appId: String?
    public let clientId: String
    public let redirectPort: UInt16

    public init(appId: String?, clientId: String, redirectPort: UInt16) {
        self.appId = appId
        self.clientId = clientId
        self.redirectPort = redirectPort
    }
}

/// What a finished setup produces: the workspace for state.json and its token for the Keychain.
public struct SlackConnection: Sendable, Equatable {
    public let workspace: Workspace
    public let credentials: SlackCredentials

    public init(workspace: Workspace, credentials: SlackCredentials) {
        self.workspace = workspace
        self.credentials = credentials
    }
}

public enum WorkspaceSetupError: Error, Equatable {
    case tokenRejected(String)   // the pasted token is expired, revoked or for another workspace
    case noFreePort
    case portBusy(UInt16)
    case cancelled               // the user clicked Cancel on Slack's page
    case slack(String)           // any other error Slack put in the redirect
    case noUserToken
    case timedOut
}

/// Connects a workspace (spec §4.4 step 2, §6.1): config token → private app → Allow in the browser → user token.
public struct WorkspaceSetup: Sendable {
    static let tokenErrors: Set<String> = ["invalid_auth", "not_authed", "token_expired", "token_revoked", "account_inactive", "invalid_token"]

    private let transport: HTTPTransport
    private let sleeper: Sleeper
    private let ports: [UInt16]
    private let timeout: Duration
    private let now: @Sendable () -> Date
    private let open: @Sendable (URL) -> Void

    public init(transport: HTTPTransport = URLSessionTransport(), sleeper: Sleeper = TaskSleeper(),
                ports: [UInt16] = SlackAppManifest.redirectPorts, timeout: Duration = .seconds(600),
                now: @escaping @Sendable () -> Date = { Date() }, open: @escaping @Sendable (URL) -> Void) {
        self.transport = transport
        self.sleeper = sleeper
        self.ports = ports
        self.timeout = timeout
        self.now = now
        self.open = open
    }

    /// Creates the private app on the first free redirect port. The config token is used for this one call and never stored.
    public func createApp(configToken: String) async throws -> SlackAppRegistration {
        var port: UInt16?
        for candidate in ports {
            guard let probe = try? LoopbackServer(port: candidate, path: SlackAppManifest.callbackPath) else { continue }
            port = probe.port
            probe.stop()
            break
        }
        guard let port else { throw WorkspaceSetupError.noFreePort }
        let created = try await rejecting {
            try await client(nil).appsManifestCreate(configToken: configToken, manifestJSON: try SlackAppManifest.json(redirectPort: port))
        }
        return SlackAppRegistration(appId: created.appId, clientId: created.credentials.clientId, redirectPort: port)
    }

    /// Opens Slack's authorize page and waits for Allow. Also used for "Finish connecting" and "Reconnect".
    public func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection {
        let pkce = PKCE.random(), state = PKCE.randomURLSafeString(byteCount: 16)
        let server: LoopbackServer
        do { server = try LoopbackServer(port: app.redirectPort, path: SlackAppManifest.callbackPath, expectedState: state) }
        catch { throw WorkspaceSetupError.portBusy(app.redirectPort) }
        open(SlackAppManifest.authorizeURL(clientId: app.clientId, redirectPort: app.redirectPort, state: state, pkce: pkce))
        let callback: LoopbackServer.Callback
        do { callback = try await server.waitForCallback(timeout: timeout) }
        catch LoopbackServer.ServerError.timedOut { throw WorkspaceSetupError.timedOut }
        if let error = callback.query["error"] { throw error == "access_denied" ? WorkspaceSetupError.cancelled : WorkspaceSetupError.slack(error) }
        guard let code = callback.query["code"], !code.isEmpty else { throw WorkspaceSetupError.slack("no_code") }
        let access = try await client(nil).oauthV2Access(clientId: app.clientId, code: code,
                                                         redirectURI: SlackAppManifest.redirectURI(port: app.redirectPort), codeVerifier: pkce.verifier)
        guard let token = access.authedUser.accessToken else { throw WorkspaceSetupError.noUserToken }
        let me = try await client(token).authTest()
        let credentials = SlackCredentials(teamId: me.teamId, userId: me.userId, accessToken: token, refreshToken: access.authedUser.refreshToken,
                                           expiresAt: access.authedUser.expiresIn.map { now().addingTimeInterval(TimeInterval($0)) }, clientId: app.clientId)
        let workspace = Workspace(teamId: me.teamId, name: me.team ?? access.team?.name ?? me.teamId, userId: me.userId, userName: me.user,
                                  url: me.url, redirectPort: app.redirectPort, appId: app.appId)
        return SlackConnection(workspace: workspace, credentials: credentials)
    }

    /// The fallback (spec §6.1): a user token pasted from an app made with the manifest link. Such tokens don't rotate.
    public func connect(userToken: String) async throws -> SlackConnection {
        let me = try await rejecting { try await client(userToken).authTest() }
        return SlackConnection(
            workspace: Workspace(teamId: me.teamId, name: me.team ?? me.teamId, userId: me.userId, userName: me.user, url: me.url, redirectPort: nil, appId: nil),
            credentials: SlackCredentials(teamId: me.teamId, userId: me.userId, accessToken: userToken, refreshToken: nil, expiresAt: nil, clientId: nil))
    }

    private func client(_ token: String?) -> SlackClient { SlackClient(token: token, transport: transport, sleeper: sleeper) }

    private func rejecting<T>(_ call: () async throws -> T) async throws -> T {
        do { return try await call() }
        catch SlackError.api(let code) where Self.tokenErrors.contains(code) { throw WorkspaceSetupError.tokenRejected(code) }
    }
}
