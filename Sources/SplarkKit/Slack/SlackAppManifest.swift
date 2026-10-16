import Foundation

/// The private per-user Slack app (spec §6.1).
public enum SlackAppManifest {
    public static let userScopes = [
        "channels:history", "groups:history", "im:history", "mpim:history",
        "channels:read", "groups:read", "im:read", "mpim:read",
        "users:read", "search:read",
        "chat:write", "reactions:write",
        "channels:write", "groups:write", "im:write", "mpim:write",
    ]

    /// Redirect ports tried in order; the first free one is used and stored with the workspace.
    public static let redirectPorts: [UInt16] = Array(53682...53691)
    public static let callbackPath = "/slack/callback"

    public static func redirectURI(port: UInt16) -> String { "http://localhost:\(port)\(callbackPath)" }

    private struct Manifest: Encodable {
        struct Display: Encodable { let name: String; let description: String }
        struct OAuth: Encodable {
            struct Scopes: Encodable { let user: [String] }
            let scopes: Scopes
            let redirect_urls: [String]?
            let pkce_enabled: Bool?
        }
        struct Settings: Encodable { let org_deploy_enabled = false, socket_mode_enabled = false, token_rotation_enabled = false }
        let display_information = Display(name: "Splark", description: "Your private Splark connection. Created by the Splark menu-bar app for your account only.")
        let oauth_config: OAuth
        let settings = Settings()
    }

    /// JSON for `apps.manifest.create`. `redirectPort == nil` gives the manual "create from manifest" variant.
    public static func json(redirectPort: UInt16?) throws -> String {
        let oauth = Manifest.OAuth(scopes: .init(user: userScopes), redirect_urls: redirectPort.map { [redirectURI(port: $0)] },
                                   pkce_enabled: redirectPort.map { _ in true })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(Manifest(oauth_config: oauth)), as: UTF8.self)
    }

    /// `https://api.slack.com/apps?new_app=1&manifest_json=…` for the manual fallback.
    public static func createFromManifestURL() throws -> URL {
        var c = URLComponents(string: "https://api.slack.com/apps")!
        c.queryItems = [URLQueryItem(name: "new_app", value: "1"), URLQueryItem(name: "manifest_json", value: try json(redirectPort: nil))]
        return c.url!
    }

    public static func authorizeURL(clientId: String, redirectPort: UInt16, state: String, pkce: PKCE) -> URL {
        var c = URLComponents(string: "https://slack.com/oauth/v2/authorize")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "user_scope", value: userScopes.joined(separator: ",")),
            URLQueryItem(name: "redirect_uri", value: redirectURI(port: redirectPort)),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return c.url!
    }
}
