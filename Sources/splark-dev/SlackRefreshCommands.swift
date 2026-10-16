import Foundation
import SplarkKit

/// What `slack-reauth` stores next to the access token, under `slack.<TEAM>.refresh`.
struct DevSlackRefresh: Codable {
    var clientId: String
    var refreshToken: String
    var expiresAt: Date
    var redirectPort: UInt16
}

/// Wraps the real transport and keeps the last response body, so a spike can print its shape.
final class TeeTransport: HTTPTransport, @unchecked Sendable {
    private let inner = URLSessionTransport()
    private(set) var lastBody = Data()
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await inner.send(request)
        lastBody = data
        return (data, response)
    }
}

/// Re-authorises an existing private app (Allow only, no config token) and stores its refresh token.
func slackReauthCommand() async throws {
    guard let clientId = option("--client-id") else { fail("pass --client-id <the app's client_id>") }
    let port = UInt16(option("--port") ?? "53682") ?? 53682
    let server = try LoopbackServer(port: port, path: SlackAppManifest.callbackPath)
    let pkce = PKCE.random(), state = PKCE.randomURLSafeString(byteCount: 16)
    print("Opening Slack. Click Allow… (port \(port))")
    openInBrowser(SlackAppManifest.authorizeURL(clientId: clientId, redirectPort: port, state: state, pkce: pkce))
    let callback = try await server.waitForCallback()
    guard callback.query["state"] == state else { fail("state mismatch") }
    if let error = callback.query["error"] { fail("Slack returned \(error)") }
    guard let code = callback.query["code"] else { fail("no code in callback") }
    let access = try await SlackClient(token: nil).oauthV2Access(clientId: clientId, code: code,
                                                                  redirectURI: SlackAppManifest.redirectURI(port: port), codeVerifier: pkce.verifier)
    guard let token = access.authedUser.accessToken, let team = access.team else { fail("no user token in response") }
    guard let refresh = access.authedUser.refreshToken, let expiresIn = access.authedUser.expiresIn else { fail("no refresh token: the token doesn't rotate") }
    let saved = DevSlackRefresh(clientId: clientId, refreshToken: refresh, expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)), redirectPort: port)
    try store.write(token, for: "slack.\(team.id)")
    try store.write(team.id, for: "slack.last")
    try store.write(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self), for: "slack.\(team.id).refresh")
    print("Reconnected \(team.name ?? team.id) as \(access.authedUser.id). token \(mask(token)), refresh \(mask(refresh)), expires \(saved.expiresAt.formatted())")
}

/// Live check for spec §6.1: does `oauth.v2.access grant_type=refresh_token` work without the client secret?
/// `--with-secret` reads the app's client secret from the clipboard (then clears it) for the fallback.
func slackRefreshCommand() async throws {
    guard let team = try option("--team") ?? store.read("slack.last"),
          let oldToken = try store.read("slack.\(team)"),
          let json = try store.read("slack.\(team).refresh") else { fail("no refresh token stored; run slack-reauth first") }
    var saved = try JSONDecoder().decode(DevSlackRefresh.self, from: Data(json.utf8))
    var secret: String?
    if args.contains("--with-secret") {
        secret = try ProcessRunner().run("/usr/bin/pbpaste", []).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try ProcessRunner().run("/bin/sh", ["-c", "printf '' | /usr/bin/pbcopy"])
        guard !(secret ?? "").isEmpty else { fail("clipboard is empty") }
    }
    print("Refreshing \(team) with client_id \(saved.clientId), \(secret == nil ? "no client secret" : "client secret from clipboard")…")
    let tee = TeeTransport()
    let refreshed: SlackTokenRefresh
    do {
        refreshed = try await SlackClient(token: nil, transport: tee).oauthV2Refresh(clientId: saved.clientId, refreshToken: saved.refreshToken, clientSecret: secret)
    } catch {
        print("refresh FAILED: \(error)")
        print("response shape: \(shape(tee.lastBody))")
        return
    }
    print("response shape: \(shape(tee.lastBody))")
    guard let newToken = refreshed.userAccessToken, let newRefresh = refreshed.userRefreshToken else { fail("no token in the refresh response") }
    let me = try await SlackClient(token: newToken).authTest()
    print("new token \(mask(newToken)) works: auth.test → \(me.user ?? me.userId) @ \(me.team ?? me.teamId)")
    print("refresh token changed: \(newRefresh != saved.refreshToken) · expires_in: \(refreshed.userExpiresIn.map(String.init) ?? "none")")
    do { _ = try await SlackClient(token: oldToken).authTest(); print("old access token: still valid") }
    catch { print("old access token: \(error)") }
    let oldRefresh = saved.refreshToken
    saved.refreshToken = newRefresh
    saved.expiresAt = Date().addingTimeInterval(TimeInterval(refreshed.userExpiresIn ?? 43200))
    try store.write(newToken, for: "slack.\(team)")
    try store.write(String(decoding: try JSONEncoder().encode(saved), as: UTF8.self), for: "slack.\(team).refresh")
    print("stored the new token; expires \(saved.expiresAt.formatted())")
    if newRefresh != oldRefresh {
        do {
            let again = try await SlackClient(token: nil).oauthV2Refresh(clientId: saved.clientId, refreshToken: oldRefresh, clientSecret: secret)
            print("old refresh token: still accepted (gave \(mask(again.userAccessToken ?? "")))")
        } catch { print("old refresh token: \(error)") }
    }
}

/// JSON keys with every string value masked, e.g. {"access_token":"xoxe.xoxp…abcd","ok":true}.
func shape(_ data: Data) -> String {
    func redact(_ value: Any) -> Any {
        switch value {
        case let s as String: return mask(s)
        case let d as [String: Any]: return d.mapValues(redact)
        case let a as [Any]: return a.map(redact)
        default: return value
        }
    }
    guard let object = try? JSONSerialization.jsonObject(with: data),
          let out = try? JSONSerialization.data(withJSONObject: redact(object), options: [.sortedKeys]) else {
        return "(not JSON, \(data.count) bytes)"
    }
    return String(decoding: out, as: UTF8.self)
}
