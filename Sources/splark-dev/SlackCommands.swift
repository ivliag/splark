import Foundation
import SplarkKit

/// Dev-tool secrets live under their own Keychain service, separate from the app's "dev.splark.Splark".
let store = KeychainStore(service: "dev.splark.dev")

func slackConnectCommand() async throws {
    if let userToken = option("--user-token") {
        let me = try await SlackClient(token: userToken).authTest()
        try store.write(userToken, for: "slack.\(me.teamId)")
        try store.write(me.teamId, for: "slack.last")
        print("Stored user token \(mask(userToken)) for \(me.team ?? me.teamId) as \(me.user ?? me.userId).")
        return
    }
    guard let configToken = option("--config-token") else { fail("pass --config-token xoxe.xoxp-… (or --user-token xoxp-…)") }
    var server: LoopbackServer?
    var port: UInt16 = 0
    for candidate in SlackAppManifest.redirectPorts {
        if let s = try? LoopbackServer(port: candidate, path: SlackAppManifest.callbackPath) { server = s; port = candidate; break }
    }
    guard let server else { fail("no free port in \(SlackAppManifest.redirectPorts)") }
    let slack = SlackClient(token: nil)
    print("1/3 Creating your private Slack app (redirect port \(port))…")
    let created = try await slack.appsManifestCreate(configToken: configToken, manifestJSON: SlackAppManifest.json(redirectPort: port))
    print("    app \(created.appId), client \(created.credentials.clientId)")
    let pkce = PKCE.random(), state = PKCE.randomURLSafeString(byteCount: 16)
    let authorize = SlackAppManifest.authorizeURL(clientId: created.credentials.clientId, redirectPort: port, state: state, pkce: pkce)
    print("2/3 Opening Slack. Click Allow… (\(authorize.absoluteString.prefix(80))…)")
    openInBrowser(authorize)
    let callback = try await server.waitForCallback()
    guard callback.query["state"] == state else { fail("state mismatch") }
    if let error = callback.query["error"] { fail("Slack returned \(error)") }
    guard let code = callback.query["code"] else { fail("no code in callback: \(callback.query)") }
    print("3/3 Exchanging the code (PKCE, no client secret)…")
    let access = try await slack.oauthV2Access(clientId: created.credentials.clientId, code: code,
                                               redirectURI: SlackAppManifest.redirectURI(port: port), codeVerifier: pkce.verifier)
    guard let token = access.authedUser.accessToken, let team = access.team else { fail("no user token in response") }
    try store.write(token, for: "slack.\(team.id)")
    try store.write(team.id, for: "slack.last")
    print("""
    Connected \(team.name ?? team.id) as \(access.authedUser.id).
      token: \(mask(token)) (type \(access.authedUser.tokenType ?? "?"))
      refresh token: \(access.authedUser.refreshToken == nil ? "none" : "present") · expires_in: \(access.authedUser.expiresIn.map(String.init) ?? "none")
      scopes: \(access.authedUser.scope ?? "?")
    """)
}

func slackProbeCommand() async throws {
    guard let team = try option("--team") ?? store.read("slack.last"), let token = try store.read("slack.\(team)") else {
        fail("no stored Slack token; run slack-connect first")
    }
    let slack = SlackClient(token: token)
    let me = try await slack.authTest()
    print("auth.test: \(me.user ?? me.userId) @ \(me.team ?? me.teamId)")

    let started = Date()
    let all = try await slack.allConversations()
    let byKind = Dictionary(grouping: all, by: \.kind).mapValues(\.count)
    print("users.conversations: \(all.count) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s · \(byKind)")

    let sample = Array(all.filter { $0.kind == .im }.prefix(5)) + Array(all.filter { $0.kind != .im }.prefix(5))
    for conversation in sample {
        let info = try await slack.conversationsInfo(conversation.id)
        let unread = try await slack.conversationsHistory(conversation.id, oldest: info.lastRead, limit: 40).messages.count
        print("  \(conversation.kind) \(info.name ?? conversation.id): last_read=\(info.lastRead ?? "nil") unread_count_display=\(info.unreadCountDisplay.map(String.init) ?? "nil") unread_fetched=\(unread)")
    }

    if let busy = all.first(where: { $0.kind == .publicChannel }) {
        let page = try await slack.conversationsHistory(busy.id, oldest: nil, limit: 100)
        print("clamp check on \(busy.name ?? busy.id): asked 100, got \(page.messages.count), has_more=\(page.hasMore ?? false)")
        let t = Date()
        for _ in 0..<3 { _ = try await slack.conversationsHistory(busy.id, oldest: nil, limit: 5) }
        print("3 more history calls took \(String(format: "%.1f", Date().timeIntervalSince(t))) s (≈60 s+ means the 1/min clamp applies)")
    }

    for query in ["<@\(me.userId)>", "@\(me.user ?? me.userId)"] {
        let result = try await slack.searchMessages(query, count: 5)
        print("search.messages \(query): total=\(result.messages.total ?? -1) sample=\(result.messages.matches.map { $0.channel.name ?? $0.channel.id })")
    }
}
