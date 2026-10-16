import Foundation
import Testing
@testable import SplarkKit

@Suite struct SlackAppManifestTests {
    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func pkceManifestHasRedirectScopesAndNoRotation() throws {
        let m = try object(SlackAppManifest.json(redirectPort: 53682))
        let oauth = try #require(m["oauth_config"] as? [String: Any])
        #expect(oauth["redirect_urls"] as? [String] == ["http://localhost:53682/slack/callback"])
        #expect(oauth["pkce_enabled"] as? Bool == true)
        let scopes = try #require((oauth["scopes"] as? [String: Any])?["user"] as? [String])
        #expect(scopes.count == 16)
        #expect(scopes.contains("search:read") && scopes.contains("mpim:write"))
        let settings = try #require(m["settings"] as? [String: Any])
        #expect(settings["token_rotation_enabled"] as? Bool == false)
        #expect((m["display_information"] as? [String: Any])?["name"] as? String == "Splark")
    }

    @Test func manualManifestHasNoRedirectOrPKCE() throws {
        let oauth = try #require(try object(SlackAppManifest.json(redirectPort: nil))["oauth_config"] as? [String: Any])
        #expect(oauth["redirect_urls"] == nil)
        #expect(oauth["pkce_enabled"] == nil)
    }

    @Test func authorizeURLCarriesPKCEAndUserScopes() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = SlackAppManifest.authorizeURL(clientId: "1.2", redirectPort: 53683, state: "st", pkce: pkce)
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.host == "slack.com" && url.path == "/oauth/v2/authorize")
        #expect(items["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["redirect_uri"] == "http://localhost:53683/slack/callback")
        #expect(items["user_scope"]?.split(separator: ",").count == 16)
        #expect(items["scope"] == nil)
    }

    @Test func createFromManifestURLEmbedsManualManifest() throws {
        let url = SlackAppManifest.createFromManifestURL()
        let manifest = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "manifest_json" }?.value
        #expect(manifest == SlackAppManifest.json(redirectPort: nil))
    }
}
