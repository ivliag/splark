import Foundation

/// Stored after "Sign in with ChatGPT" (spec §7.1). Persisted as JSON in the SecretStore under `ChatGPTAuth.secretKey`.
public struct ChatGPTCredentials: Codable, Sendable, Equatable {
    public var clientId: String          // "oaiapp_…" once issued
    public var hostId: String            // ext_agent_host_id, stable per Mac
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var expiresAt: Date
    public var scopes: [String]
    public var email: String?
    public var subject: String?

    public var canUsePlan: Bool { scopes.contains("chatgpt.tokens.use.direct") }
    public func needsRefresh(now: Date) -> Bool { expiresAt.timeIntervalSince(now) < 300 }
}

public enum ChatGPTAuthError: Error, Equatable { case stateMismatch, missingCode, http(Int, String), decoding(String) }

public struct ChatGPTAuth: Sendable {
    public static let authorizeEndpoint = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    public static let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    public static let dynamicClientId = "dynamic_agent_client"
    public static let agentName = "Splark"
    public static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    public static let resource = "https://api.openai.com/v1"
    public static let secretKey = "chatgpt"

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let transport: HTTPTransport
    private let now: @Sendable () -> Date
    public init(transport: HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    public static func redirectURI(port: UInt16) -> String { "http://127.0.0.1:\(port)/callback" }

    /// A new `ext_agent_host_id`. OpenAI rejects anything but a lowercase RFC 4122 URN ("urn:uuid:…").
    /// Generate once per Mac and persist it with the credentials.
    public static func newHostId() -> String { "urn:uuid:" + UUID().uuidString.lowercased() }

    /// `clientId == nil` means first sign-in (dynamic registration).
    public static func authorizeURL(clientId: String?, hostId: String, port: UInt16, state: String, nonce: String, pkce: PKCE, loginHint: String? = nil) -> URL {
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId ?? dynamicClientId),
            URLQueryItem(name: "ext_agent_host_id", value: hostId),
            URLQueryItem(name: "redirect_uri", value: redirectURI(port: port)),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        if clientId == nil { items.append(URLQueryItem(name: "agent_name_hint", value: agentName)) }
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        var c = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = items
        return c.url!
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let expiresIn: Double?
        let scope: String?
    }

    /// Exchanges the callback for credentials. The callback may carry the newly issued `client_id`.
    public func exchange(callback: [String: String], expectedState: String, pkce: PKCE, port: UInt16, hostId: String, priorClientId: String?) async throws -> ChatGPTCredentials {
        guard callback["state"] == expectedState else { throw ChatGPTAuthError.stateMismatch }
        guard let code = callback["code"], !code.isEmpty else { throw ChatGPTAuthError.missingCode }
        let clientId = callback["client_id"] ?? priorClientId ?? Self.dynamicClientId
        let token = try await tokenRequest([
            "grant_type": "authorization_code", "code": code, "client_id": clientId,
            "code_verifier": pkce.verifier, "redirect_uri": Self.redirectURI(port: port), "resource": Self.resource,
        ])
        let claims = token.idToken.flatMap(Self.claims(fromJWT:)) ?? [:]
        return ChatGPTCredentials(
            clientId: clientId, hostId: hostId, accessToken: token.accessToken, refreshToken: token.refreshToken,
            idToken: token.idToken, expiresAt: now().addingTimeInterval(token.expiresIn ?? 3600),
            scopes: (token.scope ?? "").split(separator: " ").map(String.init),
            email: claims["email"] as? String, subject: claims["sub"] as? String)
    }

    public func refresh(_ credentials: ChatGPTCredentials) async throws -> ChatGPTCredentials {
        guard let refreshToken = credentials.refreshToken else { throw ChatGPTAuthError.missingCode }
        let token = try await tokenRequest([
            "grant_type": "refresh_token", "refresh_token": refreshToken,
            "client_id": credentials.clientId, "resource": Self.resource,
        ])
        var updated = credentials
        updated.accessToken = token.accessToken
        updated.refreshToken = token.refreshToken ?? refreshToken
        updated.idToken = token.idToken ?? credentials.idToken
        updated.expiresAt = now().addingTimeInterval(token.expiresIn ?? 3600)
        if let scope = token.scope { updated.scopes = scope.split(separator: " ").map(String.init) }
        return updated
    }

    private func tokenRequest(_ params: [String: String]) async throws -> TokenResponse {
        let (data, response) = try await transport.send(.form(Self.tokenEndpoint, params))
        guard response.statusCode == 200 else { throw ChatGPTAuthError.http(response.statusCode, String(decoding: data, as: UTF8.self)) }
        do { return try Self.decoder.decode(TokenResponse.self, from: data) }
        catch { throw ChatGPTAuthError.decoding("\(error)") }
    }

    /// Reads (does not verify) the JWT payload; used only for display (email) and identity (sub).
    public static func claims(fromJWT jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
