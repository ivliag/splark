import Foundation

/// The Slack methods Plan 1 needs (spec §6.2). Plan 2 adds the rest.
extension SlackClient {
    public func authTest() async throws -> SlackAuthTest {
        try await call("auth.test", tier: .tier4)
    }

    /// One page of the conversations the user is in.
    public func usersConversations(cursor: String? = nil) async throws -> SlackConversationList {
        var p = ["types": "public_channel,private_channel,mpim,im", "exclude_archived": "true", "limit": "200"]
        if let cursor { p["cursor"] = cursor }
        return try await call("users.conversations", tier: .tier3, params: p)
    }

    /// All pages of `usersConversations`.
    public func allConversations() async throws -> [SlackConversation] {
        var all: [SlackConversation] = []
        var cursor: String?
        repeat {
            let page = try await usersConversations(cursor: cursor)
            all += page.channels
            cursor = page.responseMetadata?.nextCursor
        } while !(cursor ?? "").isEmpty
        return all
    }

    public func conversationsInfo(_ channel: String) async throws -> SlackConversation {
        let r: SlackConversationInfo = try await call("conversations.info", tier: .tier3, params: ["channel": channel])
        return r.channel
    }

    /// Messages newer than `oldest` (exclusive), newest first, as Slack returns them.
    public func conversationsHistory(_ channel: String, oldest: String?, limit: Int) async throws -> SlackHistory {
        var p = ["channel": channel, "limit": String(limit)]
        if let oldest { p["oldest"] = oldest }
        return try await call("conversations.history", tier: .tier3, params: p)
    }

    public func searchMessages(_ query: String, count: Int = 20) async throws -> SlackSearchResult {
        try await call("search.messages", tier: .tier2, params: ["query": query, "sort": "timestamp", "sort_dir": "desc", "count": String(count)])
    }

    /// Creates an app from a manifest with an app configuration token (`xoxe.xoxp-…`).
    public func appsManifestCreate(configToken: String, manifestJSON: String) async throws -> SlackManifestCreate {
        try await call("apps.manifest.create", tier: .tier1, params: ["manifest": manifestJSON], bearer: configToken)
    }

    /// PKCE code exchange: no client secret, no bearer token.
    public func oauthV2Access(clientId: String, code: String, redirectURI: String, codeVerifier: String) async throws -> SlackOAuthAccess {
        try await call("oauth.v2.access", tier: .tier4,
                       params: ["client_id": clientId, "code": code, "redirect_uri": redirectURI, "code_verifier": codeVerifier],
                       bearer: "")
    }
}
