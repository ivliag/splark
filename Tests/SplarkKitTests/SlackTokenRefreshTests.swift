import Foundation
import Testing
@testable import SplarkKit

@Suite struct SlackTokenRefreshTests {
    @Test func refreshSendsGrantAndNoSecretOrAuthHeader() async throws {
        let stub = StubTransport(json: #"{"ok":true,"access_token":"xoxe.xoxp-2","refresh_token":"xoxe-1-r2","expires_in":43200,"token_type":"user"}"#)
        let r = try await SlackClient(token: nil, transport: stub, sleeper: RecordingSleeper())
            .oauthV2Refresh(clientId: "123.456", refreshToken: "xoxe-1-r1")
        #expect(stub.formBody(0) == ["client_id": "123.456", "grant_type": "refresh_token", "refresh_token": "xoxe-1-r1"])
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(r.userAccessToken == "xoxe.xoxp-2")
        #expect(r.userRefreshToken == "xoxe-1-r2")
        #expect(r.userExpiresIn == 43200)
    }

    @Test func refreshSendsClientSecretWhenGiven() async throws {
        let stub = StubTransport(json: #"{"ok":true,"access_token":"a","refresh_token":"r","expires_in":43200,"token_type":"user"}"#)
        _ = try await SlackClient(token: nil, transport: stub, sleeper: RecordingSleeper())
            .oauthV2Refresh(clientId: "1.2", refreshToken: "r1", clientSecret: "s3cret")
        #expect(stub.formBody(0)["client_secret"] == "s3cret")
    }

    @Test func refreshReadsTheAuthedUserShapeToo() async throws {
        let stub = StubTransport(json: #"{"ok":true,"authed_user":{"id":"U1","access_token":"xoxe.xoxp-3","refresh_token":"xoxe-1-r3","expires_in":43100,"token_type":"user"}}"#)
        let r = try await SlackClient(token: nil, transport: stub, sleeper: RecordingSleeper())
            .oauthV2Refresh(clientId: "1.2", refreshToken: "r1")
        #expect(r.userAccessToken == "xoxe.xoxp-3")
        #expect(r.userRefreshToken == "xoxe-1-r3")
        #expect(r.userExpiresIn == 43100)
    }
}
