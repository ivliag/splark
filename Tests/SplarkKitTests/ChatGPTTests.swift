import Foundation
import Testing
@testable import SplarkKit

@Suite struct ChatGPTAuthTests {
    private func query(_ url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func firstSignInUsesDynamicClientAndAgentName() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = ChatGPTAuth.authorizeURL(clientId: nil, hostId: "host-1", port: 50111, state: "s", nonce: "n", pkce: pkce)
        let q = query(url)
        #expect(url.absoluteString.hasPrefix("https://auth.openai.com/api/accounts/authorize?"))
        #expect(q["client_id"] == "dynamic_agent_client")
        #expect(q["agent_name_hint"] == "Splark")
        #expect(q["redirect_uri"] == "http://127.0.0.1:50111/callback")
        #expect(q["scope"] == "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        #expect(q["resource"] == "https://api.openai.com/v1")
        #expect(q["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(q["ext_agent_host_id"] == "host-1")
    }

    @Test func newHostIdIsALowercaseUUIDURN() {
        let id = ChatGPTAuth.newHostId()
        #expect(id.range(of: #"^urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: .regularExpression) != nil)
        #expect(ChatGPTAuth.newHostId() != id)
    }

    @Test func reauthorizationUsesIssuedClientAndOmitsAgentName() {
        let q = query(ChatGPTAuth.authorizeURL(clientId: "oaiapp_123", hostId: "h", port: 1, state: "s", nonce: "n", pkce: .random()))
        #expect(q["client_id"] == "oaiapp_123")
        #expect(q["agent_name_hint"] == nil)
    }

    @Test func exchangeChecksStateAndReadsIssuedClientId() async throws {
        let idToken = "x." + Data(#"{"sub":"user-1","email":"ivan@lumen.dev"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "") + ".y"
        let stub = StubTransport(json: #"{"access_token":"at","refresh_token":"rt","id_token":"\#(idToken)","expires_in":3600,"scope":"openid chatgpt.tokens.use.direct"}"#)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let auth = ChatGPTAuth(transport: stub, now: { start })
        let pkce = PKCE(verifier: "v")
        await #expect(throws: ChatGPTAuthError.stateMismatch) {
            try await auth.exchange(callback: ["code": "c", "state": "wrong"], expectedState: "s", pkce: pkce, port: 9, hostId: "h", priorClientId: nil)
        }
        let creds = try await auth.exchange(callback: ["code": "c", "state": "s", "client_id": "oaiapp_9"], expectedState: "s", pkce: pkce, port: 9, hostId: "h", priorClientId: nil)
        #expect(creds.clientId == "oaiapp_9")
        #expect(creds.email == "ivan@lumen.dev" && creds.subject == "user-1")
        #expect(creds.canUsePlan)
        #expect(creds.expiresAt == start.addingTimeInterval(3600))
        #expect(stub.formBody(0)["client_id"] == "oaiapp_9")
        #expect(stub.formBody(0)["code_verifier"] == "v")
        #expect(stub.formBody(0)["redirect_uri"] == "http://127.0.0.1:9/callback")
    }

    @Test func cancelledSignInNeverCallsTheTokenEndpoint() async {
        let stub = StubTransport(json: #"{"access_token":"should-not-be-used"}"#)
        let auth = ChatGPTAuth(transport: stub)
        await #expect(throws: ChatGPTAuthError.denied(error: "access_denied", description: "User cancelled")) {
            try await auth.exchange(callback: ["error": "access_denied", "error_description": "User cancelled", "state": "s"], expectedState: "s", pkce: .random(), port: 1, hostId: "h", priorClientId: nil)
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func refreshKeepsOldRefreshTokenWhenNoneReturned() async throws {
        let stub = StubTransport(json: #"{"access_token":"at2","expires_in":60}"#)
        let start = Date(timeIntervalSince1970: 0)
        let old = ChatGPTCredentials(clientId: "oaiapp_1", hostId: "h", accessToken: "at1", refreshToken: "rt1", idToken: nil,
                                     expiresAt: start, scopes: ["chatgpt.tokens.use.direct"], email: nil, subject: nil)
        let new = try await ChatGPTAuth(transport: stub, now: { start }).refresh(old)
        #expect(new.accessToken == "at2" && new.refreshToken == "rt1")
        #expect(new.needsRefresh(now: start))   // expires in 60 s < 5 min
        #expect(stub.formBody(0)["grant_type"] == "refresh_token")
    }

    @Test func refreshWithoutARefreshTokenSaysSo() async {
        let creds = ChatGPTCredentials(clientId: "c", hostId: "h", accessToken: "a", refreshToken: nil, idToken: nil,
                                       expiresAt: Date(timeIntervalSince1970: 0), scopes: [], email: nil, subject: nil)
        await #expect(throws: ChatGPTAuthError.missingRefreshToken) { try await ChatGPTAuth(transport: StubTransport([])).refresh(creds) }
    }
}

@Suite struct OpenAIResponsesTests {
    @Test func parserAccumulatesDeltasAcrossArbitraryChunks() {
        let stream = """
        event: response.created
        data: {"type":"response.created"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"{\\"items\\":"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"[]}"}

        event: response.completed
        data: {"type":"response.completed","response":{"status":"completed"}}

        """
        var parser = ResponseStreamParser()
        var index = stream.startIndex
        while index < stream.endIndex {
            let next = stream.index(index, offsetBy: 7, limitedBy: stream.endIndex) ?? stream.endIndex
            parser.feed(String(stream[index..<next]))
            index = next
        }
        #expect(parser.text == #"{"items":[]}"#)
        #expect(parser.completed && parser.failure == nil)
    }

    @Test func parserCapturesFailure() {
        var parser = ResponseStreamParser()
        parser.feed(#"data: {"type":"response.failed","response":{"error":{"message":"usage limit reached"}}}"# + "\n")
        #expect(parser.failure == "usage limit reached")
    }

    @Test func bodyAlwaysStreamsWithStorageOff() throws {
        let data = try OpenAIClient.responsesBody(model: "m", instructions: "i", input: "x", schemaName: "triage", schema: ["type": "object"])
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["stream"] as? Bool == true && body["store"] as? Bool == false)
        #expect(body["instructions"] as? String == "i")
        #expect(body["temperature"] == nil && body["max_output_tokens"] == nil)
        let format = try #require(((body["text"] as? [String: Any])?["format"]) as? [String: Any])
        #expect(format["type"] as? String == "json_schema" && format["strict"] as? Bool == true)
    }

    @Test func inputIsSentAsAListWithOneUserMessage() throws {
        let data = try OpenAIClient.responsesBody(model: "m", instructions: "i", input: "hello", schemaName: nil, schema: nil)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect(input[0]["type"] as? String == "message" && input[0]["role"] as? String == "user")
        let content = try #require(input[0]["content"] as? [[String: Any]])
        #expect(content.count == 1 && content[0]["type"] as? String == "input_text" && content[0]["text"] as? String == "hello")
    }

    @Test func listModelsReadsThePlanShapeAndSkipsHiddenModels() async throws {
        let stub = StubTransport(json: #"{"models":[{"slug":"gpt-6-luna","visibility":"list","supported_in_api":true},{"slug":"codex-auto-review","visibility":"hide","supported_in_api":true},{"slug":"gpt-5.6-luna","visibility":"list","supported_in_api":true},{"slug":"web-only","visibility":"list","supported_in_api":false}]}"#)
        #expect(try await OpenAIClient(transport: stub).listModels(accessToken: "t") == ["gpt-5.6-luna", "gpt-6-luna"])
    }

    @Test func bodyRejectsASchemaThatIsNotJSON() {
        #expect(throws: (any Error).self) {
            try OpenAIClient.responsesBody(model: "m", instructions: "i", input: "x", schemaName: "s", schema: ["bad": Date()])
        }
    }

    @Test func respondSplitsTheStreamOnlyOnNewlines() async throws {
        // U+2028 is legal inside a JSON string. Splitting on it (as AsyncBytes.lines does) would cut the event in half.
        let sse = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"a\u{2028}b\"}\n\ndata: {\"type\":\"response.completed\"}\n\n"
        let client = OpenAIClient(streamer: { request in
            (OpenAIClient.ByteStream { c in for b in Array(sse.utf8) { c.yield(b) }; c.finish() },
             HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        #expect(try await client.respond(accessToken: "t", model: "m", instructions: "i", input: "x") == "a\u{2028}b")
    }

    @Test func listModelsSortsIds() async throws {
        let stub = StubTransport(json: #"{"object":"list","data":[{"id":"gpt-b"},{"id":"gpt-a"}]}"#)
        #expect(try await OpenAIClient(transport: stub).listModels(accessToken: "t") == ["gpt-a", "gpt-b"])
        #expect(stub.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }
}
