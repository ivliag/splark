import Foundation
import Testing
@testable import SplarkKit

@Suite struct SlackClientTests {
    @Test func postsFormWithBearerAndDecodesSnakeCase() async throws {
        let stub = StubTransport(json: #"{"ok":true,"user_id":"U1","user":"ivan","team_id":"T1","team":"Lumen","url":"https://lumen.slack.com/"}"#)
        let client = SlackClient(token: "xoxp-test", transport: stub, sleeper: RecordingSleeper())
        let me = try await client.authTest()
        #expect(me == SlackAuthTest(userId: "U1", user: "ivan", teamId: "T1", team: "Lumen", url: "https://lumen.slack.com/"))
        let request = stub.requests[0]
        #expect(request.url?.absoluteString == "https://slack.com/api/auth.test")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer xoxp-test")
    }

    @Test func okFalseBecomesApiError() async {
        let client = SlackClient(token: "x", transport: StubTransport(json: #"{"ok":false,"error":"invalid_auth"}"#), sleeper: RecordingSleeper())
        await #expect(throws: SlackError.api("invalid_auth")) { try await client.authTest() }
    }

    @Test func retriesAfter429UsingRetryAfter() async throws {
        let stub = StubTransport([
            .init(status: 429, body: "", headers: ["Retry-After": "7"]),
            .init(status: 200, body: #"{"ok":true,"user_id":"U1","team_id":"T1"}"#, headers: [:]),
        ])
        let sleeper = RecordingSleeper()
        let client = SlackClient(token: "x", transport: stub, sleeper: sleeper)
        _ = try await client.authTest()
        #expect(stub.requests.count == 2)
        #expect(sleeper.slept.contains { $0 >= 6.9 && $0 <= 7.1 })
    }

    @Test func givesUpAfterThree429s() async {
        let r = StubTransport.Reply(status: 429, body: "", headers: ["Retry-After": "1"])
        let client = SlackClient(token: "x", transport: StubTransport([r, r, r]), sleeper: RecordingSleeper())
        await #expect(throws: SlackError.rateLimited(retryAfter: 1)) { try await client.authTest() }
    }

    @Test func htmlErrorPageBecomesHTTPError() async {
        let stub = StubTransport([.init(status: 503, body: "<html>Service Unavailable</html>", headers: [:])])
        let client = SlackClient(token: "x", transport: stub, sleeper: RecordingSleeper())
        await #expect(throws: SlackError.http(503)) { try await client.authTest() }
    }

    @Test func missingRetryAfterWaitsThirtySeconds() async throws {
        let stub = StubTransport([
            .init(status: 429, body: "", headers: [:]),
            .init(status: 200, body: #"{"ok":true,"user_id":"U1","team_id":"T1"}"#, headers: [:]),
        ])
        let sleeper = RecordingSleeper()
        _ = try await SlackClient(token: "x", transport: stub, sleeper: sleeper).authTest()
        #expect(sleeper.slept.contains { abs($0 - 30) < 0.1 })
    }

    @Test func allConversationsFollowsCursors() async throws {
        let stub = StubTransport(json:
            #"{"ok":true,"channels":[{"id":"D1","is_im":true,"user":"U2"}],"response_metadata":{"next_cursor":"abc"}}"#,
            #"{"ok":true,"channels":[{"id":"C1","name":"eng","is_channel":true,"is_private":false}],"response_metadata":{"next_cursor":""}}"#)
        let all = try await SlackClient(token: "x", transport: stub, sleeper: RecordingSleeper()).allConversations()
        #expect(all.map(\.id) == ["D1", "C1"])
        #expect(all.map(\.kind) == [.im, .publicChannel])
        #expect(stub.formBody(1)["cursor"] == "abc")
        #expect(stub.formBody(0)["types"] == "public_channel,private_channel,mpim,im")
    }

    @Test func oauthExchangeSendsVerifierAndNoAuthHeader() async throws {
        let stub = StubTransport(json: #"{"ok":true,"app_id":"A1","authed_user":{"id":"U1","scope":"im:history","access_token":"xoxp-1","token_type":"user"},"team":{"id":"T1","name":"Lumen"}}"#)
        let r = try await SlackClient(token: nil, transport: stub, sleeper: RecordingSleeper())
            .oauthV2Access(clientId: "123.456", code: "c0de", redirectURI: "http://localhost:53682/slack/callback", codeVerifier: "v3r")
        #expect(r.authedUser.accessToken == "xoxp-1")
        #expect(r.team?.name == "Lumen")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(stub.formBody(0) == ["client_id": "123.456", "code": "c0de", "redirect_uri": "http://localhost:53682/slack/callback", "code_verifier": "v3r"])
    }

    @Test func manifestCreateUsesConfigTokenAsBearer() async throws {
        let stub = StubTransport(json: #"{"ok":true,"app_id":"A9","credentials":{"client_id":"1.2","client_secret":"s"},"oauth_authorize_url":"https://slack.com/oauth/v2/authorize?client_id=1.2"}"#)
        let r = try await SlackClient(token: nil, transport: stub, sleeper: RecordingSleeper())
            .appsManifestCreate(configToken: "xoxe.xoxp-cfg", manifestJSON: #"{"a":1}"#)
        #expect(r.appId == "A9")
        #expect(r.credentials.clientId == "1.2")
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer xoxe.xoxp-cfg")
        #expect(stub.formBody(0)["manifest"] == #"{"a":1}"#)
    }
}

@Suite struct RateLimiterTests {
    @Test func allowsTierBudgetThenWaitsForOldestToExpire() async {
        let clock = ManualClock()
        let limiter = RateLimiter(now: { clock.now })
        for _ in 0..<20 { #expect(await limiter.reserve("search.messages", tier: .tier2) == 0) }
        clock.advance(10)
        let wait = await limiter.reserve("search.messages", tier: .tier2)
        #expect(abs(wait - 50) < 0.001)
        #expect(await limiter.reserve("auth.test", tier: .tier4) == 0)   // other methods unaffected
    }

    @Test func queuedReservationsNeverExceedTheTierInAnyMinute() async {
        let clock = ManualClock()
        let limiter = RateLimiter(now: { clock.now })
        var starts: [TimeInterval] = []
        for _ in 0..<120 { starts.append(await limiter.reserve("conversations.info", tier: .tier3)) }
        #expect(starts.filter { $0 == 0 }.count == 50)
        #expect(starts.filter { $0 == 60 }.count == 50)
        #expect(starts.filter { $0 == 120 }.count == 20)
        let busiestMinute = starts.map { t in starts.filter { $0 >= t && $0 < t + 60 }.count }.max() ?? 0
        #expect(busiestMinute <= 50)
    }

    @Test func pauseDelaysNextCall() async {
        let clock = ManualClock()
        let limiter = RateLimiter(now: { clock.now })
        await limiter.pause("conversations.history", retryAfter: 30)
        #expect(await limiter.reserve("conversations.history", tier: .tier3) == 30)
    }
}

@Suite struct SlackFormEncodingTests {
    @Test func formRequestsCarryNoCharset() async throws {
        // Slack answers "superfluous_charset" to "application/x-www-form-urlencoded; charset=utf-8".
        let stub = StubTransport(json: #"{"ok":true,"user_id":"U1","team_id":"T1"}"#)
        _ = try await SlackClient(token: "x", transport: stub, sleeper: RecordingSleeper()).authTest()
        #expect(stub.requests[0].value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }
}
