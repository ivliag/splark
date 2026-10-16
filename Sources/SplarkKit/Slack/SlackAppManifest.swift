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

    /// JSON for `apps.manifest.create`. `redirectPort == nil` gives the manual "create from manifest" variant.
    public static func json(redirectPort: UInt16?) -> String {
        var oauth: [String: Any] = ["scopes": ["user": userScopes]]
        if let redirectPort {
            oauth["redirect_urls"] = [redirectURI(port: redirectPort)]
            oauth["pkce_enabled"] = true
        }
        let manifest: [String: Any] = [
            "display_information": [
                "name": "Splark",
                "description": "Your private Splark connection. Created by the Splark menu-bar app for your account only.",
            ],
            "oauth_config": oauth,
            "settings": ["org_deploy_enabled": false, "socket_mode_enabled": false, "token_rotation_enabled": false],
        ]
        let data = try! JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    /// `https://api.slack.com/apps?new_app=1&manifest_json=…` for the manual fallback.
    public static func createFromManifestURL() -> URL {
        var c = URLComponents(string: "https://api.slack.com/apps")!
        c.queryItems = [URLQueryItem(name: "new_app", value: "1"), URLQueryItem(name: "manifest_json", value: json(redirectPort: nil))]
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
