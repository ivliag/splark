import Foundation
import SplarkKit

/// Dev-tool secrets live under their own Keychain service, separate from the app's "dev.splark.Splark".
let store = KeychainStore(service: "dev.splark.dev")

/// Copy an app configuration token (`xoxe.xoxp-…`), or with `--manual` a user token, then run this.
func slackConnectCommand() async throws {
    let setup = WorkspaceSetup(open: openInBrowser)
    if args.contains("--manual") {
        try save(try await setup.connect(userToken: try clipboardSecret()))
        return
    }
    let app = try await setup.createApp(configToken: try clipboardSecret())
    print("Created app \(app.appId ?? "?") (client \(app.clientId), port \(app.redirectPort)). Opening Slack: click Allow…")
    try save(try await setup.authorize(app))
}

/// Re-authorises the existing app (Allow only, no config token): after the refresh token expired or scopes changed.
func slackReauthCommand() async throws {
    let stored = try await devCredentials()
    guard let clientId = option("--client-id") ?? stored?.clientId else { fail("no client_id stored; pass --client-id") }
    let port = UInt16(option("--port") ?? "53682") ?? 53682
    print("Opening Slack: click Allow…")
    try save(try await WorkspaceSetup(open: openInBrowser).authorize(SlackAppRegistration(appId: nil, clientId: clientId, redirectPort: port)))
}

/// Swaps the refresh token for a new access token now, and checks the new token works.
func slackRefreshCommand() async throws {
    guard let stored = try await devCredentials() else { fail("no stored Slack token; run slack-connect first") }
    let manager = SlackTokenManager(credentials: stored, store: store)
    let token = try await manager.refreshAfterRejection(of: stored.accessToken)
    let me = try await SlackClient(token: token).authTest()
    print("Refreshed: \(mask(token)) works for \(me.user ?? me.userId) @ \(me.team ?? me.teamId), expires \(await manager.credentials.expiresAt?.formatted() ?? "never").")
}

private func save(_ connection: SlackConnection) throws {
    try connection.credentials.save(to: store)
    try store.write(connection.workspace.teamId, for: "slack.last")
    let c = connection.credentials
    print("Connected \(connection.workspace.name) as \(connection.workspace.userName ?? c.userId). Token \(mask(c.accessToken)), refresh token \(c.refreshToken == nil ? "none" : "kept"), expires \(c.expiresAt?.formatted() ?? "never").")
}

/// The workspace to use (`--team T`, else the last connected) as a client whose token refreshes itself.
func devSlack() async throws -> (SlackClient, SlackCredentials) {
    guard let credentials = try await devCredentials() else { fail("no stored Slack token; run slack-connect first") }
    return (SlackClient(tokens: SlackTokenManager(credentials: credentials, store: store)), credentials)
}

/// Loads the dev credentials. Tokens saved before Plan 2 (a bare token under `slack.<TEAM>`, and
/// `slack.<TEAM>.refresh` from the spike) are converted to `SlackCredentials` once.
func devCredentials() async throws -> SlackCredentials? {
    guard let team = try option("--team") ?? store.read("slack.last"), let raw = try store.read(SlackCredentials.key(teamId: team)) else { return nil }
    if raw.hasPrefix("{") { return try SlackCredentials.load(teamId: team, from: store) }
    struct Legacy: Decodable { let clientId: String; let refreshToken: String; let expiresAt: Date }
    let legacy = try store.read("slack.\(team).refresh").flatMap { try? JSONDecoder().decode(Legacy.self, from: Data($0.utf8)) }
    let me = try await SlackClient(token: raw).authTest()
    let credentials = SlackCredentials(teamId: team, userId: me.userId, accessToken: raw, refreshToken: legacy?.refreshToken,
                                       expiresAt: legacy?.expiresAt, clientId: legacy?.clientId)
    try credentials.save(to: store)
    try store.delete("slack.\(team).refresh")
    return credentials
}

func slackProbeCommand() async throws {
    let (slack, _) = try await devSlack()
    let me = try await slack.authTest()
    print("auth.test: \(me.user ?? me.userId) @ \(me.team ?? me.teamId)")

    let started = Date()
    let all = try await slack.allConversations()
    let byKind = Dictionary(grouping: all, by: \.kind).mapValues(\.count)
    print("users.conversations: \(all.count) in \(String(format: "%.1f", Date().timeIntervalSince(started))) s · \(byKind)")

    let sample = Array(all.filter { $0.kind == .im }.prefix(5)) + Array(all.filter { $0.kind != .im }.prefix(5))
    for conversation in sample {
        let info = try await slack.conversationsInfo(conversation.id)
        let unread: String
        do { unread = String(try await slack.conversationsHistory(conversation.id, oldest: info.lastRead, limit: 40).messages.count) }
        catch { unread = "error \(error)" }
        print("  \(conversation.kind) \(info.name ?? conversation.id): last_read=\(info.lastRead.map { "\"\($0)\"" } ?? "nil") unread_count_display=\(info.unreadCountDisplay.map(String.init) ?? "nil") unread_fetched=\(unread)")
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
