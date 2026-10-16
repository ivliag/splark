import Foundation

/// The signed-in ChatGPT account (spec §7.1): sign-in, tokens kept fresh, sign-out.
/// The Mac's `ext_agent_host_id` outlives sign-out, under `chatgpt.host`.
public actor ChatGPTSession {
    public static let hostKey = "chatgpt.host"

    public private(set) var credentials: ChatGPTCredentials?
    private let store: SecretStore
    private let auth: ChatGPTAuth
    private let now: @Sendable () -> Date
    private var inFlight: Task<ChatGPTCredentials, Error>?
    private var generation = 0   // bumped by sign-in and sign-out, so a refresh that finishes later can't undo them

    public init(store: SecretStore, auth: ChatGPTAuth = ChatGPTAuth(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.auth = auth
        self.now = now
        credentials = (try? store.read(ChatGPTAuth.secretKey)).flatMap { $0 }.flatMap { try? JSONDecoder().decode(ChatGPTCredentials.self, from: Data($0.utf8)) }
    }

    /// A token valid now, refreshed first when it expires within 5 minutes.
    public func accessToken() async throws -> String {
        guard let credentials else { throw LLMError.signedOut }
        guard credentials.canUsePlan else { throw LLMError.notEligible }
        return credentials.needsRefresh(now: now()) ? try await refresh().accessToken : credentials.accessToken
    }

    /// Called after the API answered 401 for `token`.
    public func refreshAfterRejection(of token: String) async throws -> String {
        guard let credentials else { throw LLMError.signedOut }
        return token == credentials.accessToken ? try await refresh().accessToken : credentials.accessToken
    }

    /// Opens the browser at OpenAI's sign-in page and waits for the redirect to 127.0.0.1.
    public func signIn(open: @Sendable (URL) -> Void, timeout: Duration = .seconds(600)) async throws -> ChatGPTCredentials {
        let hostId = try credentials?.hostId ?? store.read(Self.hostKey) ?? ChatGPTAuth.newHostId()
        try store.write(hostId, for: Self.hostKey)
        let pkce = PKCE.random(), state = PKCE.randomURLSafeString(byteCount: 16), nonce = PKCE.randomURLSafeString(byteCount: 16)
        let server = try LoopbackServer(port: 0, path: "/callback", ipv4Only: true, expectedState: state)
        open(ChatGPTAuth.authorizeURL(clientId: credentials?.clientId, hostId: hostId, port: server.port, state: state, nonce: nonce,
                                      pkce: pkce, loginHint: credentials?.email))
        let callback = try await server.waitForCallback(timeout: timeout)
        let signedIn = try await auth.exchange(callback: callback.query, expectedState: state, pkce: pkce, port: server.port,
                                               hostId: hostId, priorClientId: credentials?.clientId)
        generation += 1
        try save(signedIn)
        return signedIn
    }

    public func signOut() throws {
        generation += 1
        credentials = nil
        try store.delete(ChatGPTAuth.secretKey)
    }

    private func refresh() async throws -> ChatGPTCredentials {
        if let inFlight { return try await inFlight.value }
        guard let current = credentials else { throw LLMError.signedOut }
        let started = generation
        let task = Task { [auth] in
            do { return try await auth.refresh(current) }
            catch ChatGPTAuthError.missingRefreshToken { throw LLMError.signedOut }
            catch ChatGPTAuthError.http(let status, _) where (400..<500).contains(status) { throw LLMError.signedOut }
        }
        inFlight = task
        defer { inFlight = nil }
        let refreshed = try await task.value
        guard generation == started else {
            // Signed out or in again while this refresh ran: that wins.
            if let credentials { return credentials }
            throw LLMError.signedOut
        }
        try save(refreshed)
        return refreshed
    }

    private func save(_ new: ChatGPTCredentials) throws {
        try store.write(String(decoding: try JSONEncoder().encode(new), as: UTF8.self), for: ChatGPTAuth.secretKey)
        credentials = new
    }
}
