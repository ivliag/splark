import Foundation

/// A connected workspace's user token, stored as JSON in the SecretStore under `slack.<TEAM_ID>` (spec §6.1).
public struct SlackCredentials: Codable, Sendable, Equatable {
    public var teamId: String
    public var userId: String
    public var accessToken: String
    public var refreshToken: String?   // nil for manual (non-rotating) tokens
    public var expiresAt: Date?
    public var clientId: String?       // the private app's, needed to refresh and re-authorise

    public init(teamId: String, userId: String, accessToken: String, refreshToken: String?, expiresAt: Date?, clientId: String?) {
        self.teamId = teamId
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.clientId = clientId
    }

    public static func key(teamId: String) -> String { "slack.\(teamId)" }

    public static func load(teamId: String, from store: SecretStore) throws -> SlackCredentials? {
        guard let json = try store.read(key(teamId: teamId)) else { return nil }
        return try JSONDecoder().decode(SlackCredentials.self, from: Data(json.utf8))
    }

    public func save(to store: SecretStore) throws {
        try store.write(String(decoding: try JSONEncoder().encode(self), as: UTF8.self), for: Self.key(teamId: teamId))
    }

    /// Refresh within 30 minutes of expiry. Tokens without a refresh token or expiry never need it.
    public func needsRefresh(now: Date) -> Bool {
        guard refreshToken != nil, let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < 1800
    }
}

extension SlackCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "SlackCredentials(team: \(teamId), user: \(userId), accessToken: \(Redact.token(accessToken)), refreshToken: \(Redact.token(refreshToken)), expiresAt: \(expiresAt.map { "\($0)" } ?? "nil"))"
    }
    public var debugDescription: String { description }
}

/// Where `SlackClient` gets its bearer token.
public protocol SlackTokenSource: Sendable {
    /// A token that is valid now, refreshed first if it is about to expire.
    func accessToken() async throws -> String
    /// Called after Slack answers `token_expired` for `token`.
    func refreshAfterRejection(of token: String) async throws -> String
}

/// A token that never changes: manual tokens, setup calls, tests.
struct FixedToken: SlackTokenSource {
    let token: String
    func accessToken() async throws -> String { token }
    func refreshAfterRejection(of token: String) async throws -> String { throw SlackError.api("token_expired") }
}

/// Keeps one workspace's rotating token fresh (spec §6.1). Refreshes without a client secret,
/// shares one refresh among concurrent callers, and saves the new tokens before handing them out.
public actor SlackTokenManager: SlackTokenSource {
    public typealias Refresher = @Sendable (_ clientId: String, _ refreshToken: String) async throws -> SlackTokenRefresh

    /// Slack's answers that mean the refresh token itself is no good: only these send the user back to Allow.
    static let refusals: Set<String> = ["invalid_refresh_token", "invalid_client_id", "token_revoked"]

    public private(set) var credentials: SlackCredentials
    private let store: SecretStore
    private let refresher: Refresher
    private let now: @Sendable () -> Date
    private var inFlight: Task<SlackCredentials, Error>?

    public init(credentials: SlackCredentials, store: SecretStore,
                refresher: @escaping Refresher = { try await SlackClient(token: nil).oauthV2Refresh(clientId: $0, refreshToken: $1) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.credentials = credentials
        self.store = store
        self.refresher = refresher
        self.now = now
    }

    public func accessToken() async throws -> String {
        credentials.needsRefresh(now: now()) ? try await refresh().accessToken : credentials.accessToken
    }

    public func refreshAfterRejection(of token: String) async throws -> String {
        token == credentials.accessToken ? try await refresh().accessToken : credentials.accessToken
    }

    private func refresh() async throws -> SlackCredentials {
        if let inFlight { return try await inFlight.value }
        guard let clientId = credentials.clientId, let refreshToken = credentials.refreshToken else {
            throw SlackError.refreshFailed("no_refresh_token")
        }
        let task = Task { [credentials, store, refresher, now] in
            let response: SlackTokenRefresh
            do { response = try await refresher(clientId, refreshToken) }
            catch SlackError.api(let code) where Self.refusals.contains(code) { throw SlackError.refreshFailed(code) }
            guard let token = response.userAccessToken else { throw SlackError.api("no_token_in_response") }
            // Disconnected or reconnected while we waited? Then what's stored now wins.
            guard let stored = try SlackCredentials.load(teamId: credentials.teamId, from: store) else { throw SlackError.refreshFailed("disconnected") }
            guard stored.refreshToken == refreshToken else { return stored }
            var updated = credentials
            updated.accessToken = token
            updated.refreshToken = response.userRefreshToken ?? refreshToken
            updated.expiresAt = response.userExpiresIn.map { now().addingTimeInterval(TimeInterval($0)) }
            try updated.save(to: store)
            return updated
        }
        inFlight = task
        defer { inFlight = nil }
        credentials = try await task.value
        return credentials
    }
}
