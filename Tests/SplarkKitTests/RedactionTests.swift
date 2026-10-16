import Foundation
import Testing
@testable import SplarkKit

@Suite struct RedactionTests {
    @Test func tokensAreShortenedToTellThemApart() {
        #expect(Redact.token("xoxe.xoxp-not-a-real-token") == "xoxe.xoxp…oken")
        #expect(Redact.token("short") == "…")
        #expect(Redact.token(nil) == "nil")
    }

    @Test func chatGPTCredentialsNeverPrintTokens() {
        let creds = ChatGPTCredentials(clientId: "oaiapp_1", hostId: "h", accessToken: "access-token-secret-value", refreshToken: "refresh-token-secret-value",
                                       idToken: "id-token-secret-value", expiresAt: Date(timeIntervalSince1970: 0), scopes: [], email: "a@b.c", subject: nil)
        for text in ["\(creds)", String(reflecting: creds)] {
            #expect(!text.contains("access-token-secret-value"))
            #expect(!text.contains("refresh-token-secret-value"))
            #expect(!text.contains("id-token-secret-value"))
            #expect(text.contains("oaiapp_1"))
        }
    }

    @Test func slackTokenResponsesNeverPrintTokens() throws {
        let refresh = try SlackClient.decoder.decode(SlackTokenRefresh.self, from: Data(#"{"access_token":"xoxe.xoxp-secret-access","refresh_token":"xoxe-1-secret-refresh","expires_in":43200}"#.utf8))
        let access = try SlackClient.decoder.decode(SlackOAuthAccess.self, from: Data(#"{"authed_user":{"id":"U1","access_token":"xoxe.xoxp-secret-access","refresh_token":"xoxe-1-secret-refresh"}}"#.utf8))
        for text in ["\(refresh)", String(reflecting: refresh), "\(access.authedUser)", String(reflecting: access.authedUser), String(reflecting: access)] {
            #expect(!text.contains("secret-access"))
            #expect(!text.contains("secret-refresh"))
        }
    }
}
