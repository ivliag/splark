import Foundation

/// What the sync engine and the panel's actions need from Slack (spec §6.2). `SlackClient` is the real one;
/// tests use a fake.
public protocol SlackAPI: Sendable {
    func authTest() async throws -> SlackAuthTest
    func allConversations() async throws -> [SlackConversation]
    func conversationsInfo(_ channel: String) async throws -> SlackConversation
    func conversationsHistory(_ channel: String, oldest: String?, latest: String?, inclusive: Bool, limit: Int) async throws -> SlackHistory
    func conversationsReplies(_ channel: String, ts: String, oldest: String?, limit: Int) async throws -> SlackHistory
    func usersInfo(_ user: String) async throws -> SlackUser
    func searchMessages(_ query: String, count: Int) async throws -> SlackSearchResult
    func chatPostMessage(channel: String, text: String, threadTs: String?) async throws -> SlackPostedMessage
    func reactionsAdd(channel: String, timestamp: String, name: String) async throws
    func conversationsMark(channel: String, ts: String) async throws
    func chatGetPermalink(channel: String, messageTs: String) async throws -> URL
}

extension SlackClient: SlackAPI {}

private struct SlackOK: Decodable, Sendable {}
private struct SlackPermalink: Decodable, Sendable { let permalink: URL }
private struct SlackUserInfo: Decodable, Sendable { let user: SlackUser }

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

    /// Messages between `oldest` and `latest`, newest first, as Slack returns them.
    public func conversationsHistory(_ channel: String, oldest: String?, latest: String?, inclusive: Bool, limit: Int) async throws -> SlackHistory {
        var p = ["channel": channel, "limit": String(limit)]
        if let oldest { p["oldest"] = oldest }
        if let latest { p["latest"] = latest; p["inclusive"] = String(inclusive) }
        return try await call("conversations.history", tier: .tier3, params: p)
    }

    /// Messages newer than `oldest` (exclusive), newest first.
    public func conversationsHistory(_ channel: String, oldest: String?, limit: Int) async throws -> SlackHistory {
        try await conversationsHistory(channel, oldest: oldest, latest: nil, inclusive: false, limit: limit)
    }

    /// One thread's messages, oldest first, newer than `oldest` (Slack may also include the parent).
    public func conversationsReplies(_ channel: String, ts: String, oldest: String?, limit: Int) async throws -> SlackHistory {
        var p = ["channel": channel, "ts": ts, "limit": String(limit)]
        if let oldest { p["oldest"] = oldest }
        return try await call("conversations.replies", tier: .tier3, params: p)
    }

    public func usersInfo(_ user: String) async throws -> SlackUser {
        let r: SlackUserInfo = try await call("users.info", tier: .tier4, params: ["user": user])
        return r.user
    }

    /// Slack allows about one message per second per channel.
    public func chatPostMessage(channel: String, text: String, threadTs: String?) async throws -> SlackPostedMessage {
        var p = ["channel": channel, "text": text]
        if let threadTs { p["thread_ts"] = threadTs }
        return try await call("chat.postMessage", tier: .perMinute(60), params: p)
    }

    public func reactionsAdd(channel: String, timestamp: String, name: String) async throws {
        let _: SlackOK = try await call("reactions.add", tier: .tier3, params: ["channel": channel, "timestamp": timestamp, "name": name])
    }

    /// Moves the user's read marker in `channel` to `ts`.
    public func conversationsMark(channel: String, ts: String) async throws {
        let _: SlackOK = try await call("conversations.mark", tier: .tier3, params: ["channel": channel, "ts": ts])
    }

    public func chatGetPermalink(channel: String, messageTs: String) async throws -> URL {
        let r: SlackPermalink = try await call("chat.getPermalink", tier: .tier4, params: ["channel": channel, "message_ts": messageTs])
        return r.permalink
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

    /// Swaps a refresh token for a new user token (Slack rotates PKCE user tokens every 12 h).
    /// No bearer token; `clientSecret` is sent only when given.
    public func oauthV2Refresh(clientId: String, refreshToken: String, clientSecret: String? = nil) async throws -> SlackTokenRefresh {
        var p = ["client_id": clientId, "grant_type": "refresh_token", "refresh_token": refreshToken]
        if let clientSecret { p["client_secret"] = clientSecret }
        return try await call("oauth.v2.access", tier: .tier4, params: p, bearer: "")
    }
}
