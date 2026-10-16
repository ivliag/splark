import Foundation
import Testing
@testable import SplarkKit

/// Answers like `inner`, a little later: lets a test act while a request is in flight.
final class SlowTransport: HTTPTransport, @unchecked Sendable {
    let inner: StubTransport
    init(_ inner: StubTransport) { self.inner = inner }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(100))
        return try await inner.send(request)
    }
}

/// Collects requests the fake streamer sees.
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URLRequest] = []
    func add(_ r: URLRequest) { lock.withLock { items.append(r) } }
    var all: [URLRequest] { lock.withLock { items } }
    func body(_ i: Int) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: all[i].httpBody ?? Data()) as? [String: Any]) ?? [:]
    }
}

/// A Responses API that answers each call with the next canned reply.
func fakeResponses(_ replies: [(status: Int, body: String, headers: [String: String])], log: RequestLog) -> OpenAIClient.Streamer {
    let queue = LockedBox(replies)
    return { request in
        log.add(request)
        let reply = queue.withLock { $0.isEmpty ? (status: 500, body: "{}", headers: [:]) : $0.removeFirst() }
        let stream = OpenAIClient.ByteStream { c in
            for byte in Array(reply.body.utf8) { c.yield(byte) }
            c.finish()
        }
        return (stream, HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!)
    }
}

func sse(_ text: String) -> String {
    let delta = String(decoding: try! JSONSerialization.data(withJSONObject: ["type": "response.output_text.delta", "delta": text]), as: UTF8.self)
    return "data: \(delta)\n\ndata: {\"type\":\"response.completed\"}\n\n"
}

let planModels = #"{"models":[{"slug":"gpt-5.6-luna","visibility":"list","supported_in_api":true},{"slug":"gpt-6-luna","visibility":"list","supported_in_api":true}]}"#

func signedIn(expiresIn: TimeInterval = 3600, scopes: [String] = ["chatgpt.tokens.use.direct"], at start: Date) -> ChatGPTCredentials {
    ChatGPTCredentials(clientId: "oaiapp_1", hostId: "urn:uuid:0000", accessToken: "at1", refreshToken: "rt1", idToken: nil,
                       expiresAt: start.addingTimeInterval(expiresIn), scopes: scopes, email: "ivan@lumen.dev", subject: "s")
}

func storeWith(_ credentials: ChatGPTCredentials) -> InMemorySecretStore {
    InMemorySecretStore([ChatGPTAuth.secretKey: String(decoding: try! JSONEncoder().encode(credentials), as: UTF8.self)])
}

@Suite struct ChatGPTSessionTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func signInSavesTheCredentialsAndKeepsTheHostIdAcrossSignOut() async throws {
        let store = InMemorySecretStore()
        let opened = LockedBox<[URL]>([])
        let stub = StubTransport(json: #"{"access_token":"at","refresh_token":"rt","expires_in":3600,"scope":"openid chatgpt.tokens.use.direct"}"#,
                                 #"{"access_token":"at2","refresh_token":"rt2","expires_in":3600,"scope":"openid chatgpt.tokens.use.direct"}"#)
        let session = ChatGPTSession(store: store, auth: ChatGPTAuth(transport: stub, now: { start }), now: { start })
        let browser: @Sendable (URL) -> Void = { url in
            opened.withLock { $0.append(url) }
            let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            Task { _ = try? await URLSession.shared.data(from: URL(string: "\(q["redirect_uri"]!)?code=c&state=\(q["state"]!)&client_id=oaiapp_9")!) }
        }
        let creds = try await session.signIn(open: browser)
        #expect(creds.clientId == "oaiapp_9" && creds.canUsePlan)
        #expect(try store.read(ChatGPTAuth.secretKey) != nil)
        try await session.signOut()
        #expect(await session.credentials == nil)
        #expect(try store.read(ChatGPTAuth.secretKey) == nil)
        _ = try await session.signIn(open: browser)
        let hosts = opened.value.map { url in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "ext_agent_host_id" }?.value }
        #expect(hosts.count == 2 && hosts[0] == hosts[1] && hosts[0]?.hasPrefix("urn:uuid:") == true)
    }

    @Test func signingOutDuringARefreshStaysSignedOut() async throws {
        let store = storeWith(signedIn(expiresIn: 10, at: start))
        let slow = SlowTransport(StubTransport(json: #"{"access_token":"at2","refresh_token":"rt2","expires_in":3600}"#))
        let session = ChatGPTSession(store: store, auth: ChatGPTAuth(transport: slow, now: { start }), now: { start })
        let pending = Task { try await session.accessToken() }
        try await Task.sleep(for: .milliseconds(20))
        try await session.signOut()
        await #expect(throws: LLMError.signedOut) { try await pending.value }
        #expect(await session.credentials == nil)
        #expect(try store.read(ChatGPTAuth.secretKey) == nil)
    }

    @Test func refreshesWithinFiveMinutesOfExpiryAndSaves() async throws {
        let store = storeWith(signedIn(expiresIn: 200, at: start))
        let stub = StubTransport(json: #"{"access_token":"at2","refresh_token":"rt2","expires_in":3600}"#)
        let session = ChatGPTSession(store: store, auth: ChatGPTAuth(transport: stub, now: { start }), now: { start })
        #expect(try await session.accessToken() == "at2")
        #expect(try store.read(ChatGPTAuth.secretKey)?.contains("at2") == true)
    }

    @Test func aRefusedRefreshMeansSignedOut() async {
        let stub = StubTransport([.init(status: 400, body: #"{"error":"invalid_grant"}"#, headers: [:])])
        let session = ChatGPTSession(store: storeWith(signedIn(expiresIn: 10, at: start)), auth: ChatGPTAuth(transport: stub, now: { start }), now: { start })
        await #expect(throws: LLMError.signedOut) { try await session.accessToken() }
    }

    @Test func signedOutAndIneligiblePlansSaySo() async {
        await #expect(throws: LLMError.signedOut) { try await ChatGPTSession(store: InMemorySecretStore(), now: { start }).accessToken() }
        let free = ChatGPTSession(store: storeWith(signedIn(scopes: ["openid"], at: start)), now: { start })
        await #expect(throws: LLMError.notEligible) { try await free.accessToken() }
    }
}

@Suite struct ChatGPTLLMClientTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let request = LLMRequest(instructions: "Sort these.", input: "{}", schemaName: "triage", schemaJSON: #"{"type":"object"}"#)

    func client(_ replies: [(status: Int, body: String, headers: [String: String])], log: RequestLog,
                credentials: ChatGPTCredentials? = nil, refresh: String? = nil, chosen: String? = nil) -> ChatGPTLLMClient {
        let refreshStub = StubTransport(json: refresh ?? #"{"access_token":"at2","expires_in":3600}"#)
        let session = ChatGPTSession(store: storeWith(credentials ?? signedIn(at: start)), auth: ChatGPTAuth(transport: refreshStub, now: { start }), now: { start })
        return ChatGPTLLMClient(session: session, openAI: OpenAIClient(transport: StubTransport(json: planModels), streamer: fakeResponses(replies, log: log)),
                                chosenModel: chosen, now: { start })
    }

    @Test(arguments: [
        (["gpt-5.6-luna", "gpt-6-luna"], nil as String?, "gpt-6-luna" as String?),
        (["gpt-5.6-luna", "gpt-6-luna"], "gpt-5.6-luna", "gpt-5.6-luna"),
        (["gpt-5.6-luna", "gpt-6-luna"], "gone-model", "gpt-6-luna"),
        (["gpt-5.6-luna", "o9"], nil, "gpt-5.6-luna"),
        (["o9", "o8"], nil, "o9"),
        ([], nil, nil),
    ])
    func picksTheModel(available: [String], chosen: String?, picked: String?) {
        #expect(ChatGPTLLMClient.pickModel(available: available, chosen: chosen) == picked)
    }

    @Test func sendsTheSchemaToThePickedModel() async throws {
        let log = RequestLog()
        let text = try await client([(200, sse(#"{"items":[]}"#), [:])], log: log).respond(request)
        #expect(text == #"{"items":[]}"#)
        let body = log.body(0)
        #expect(body["model"] as? String == "gpt-6-luna" && body["instructions"] as? String == "Sort these.")
        let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
        #expect(format?["name"] as? String == "triage" && (format?["schema"] as? [String: Any])?["type"] as? String == "object")
        #expect(log.all[0].value(forHTTPHeaderField: "Authorization") == "Bearer at1")
    }

    @Test(arguments: [
        (#"{"error":{"type":"usage_limit_reached","resets_in_seconds":600}}"#, [String: String](), 600.0),
        ("{}", ["Retry-After": "120"], 120),
        ("{}", [:], 1800),
    ])
    func aUsageLimitPausesUntilItResets(body: String, headers: [String: String], seconds: TimeInterval) async {
        let llm = client([(429, body, headers)], log: RequestLog())
        await #expect(throws: LLMError.usageLimited(until: start.addingTimeInterval(seconds))) { try await llm.respond(request) }
    }

    @Test func aModelThatRefusesTheSchemaIsAskedForJSONInstead() async throws {
        let log = RequestLog()
        let refused = #"{"error":{"message":"Unsupported parameter: 'text.format' with json_schema","param":"text.format"}}"#
        let llm = client([(400, refused, [:]), (200, sse("first"), [:]), (200, sse("second"), [:])], log: log)
        #expect(try await llm.respond(request) == "first")
        #expect(try await llm.respond(request) == "second")
        #expect(log.all.count == 3)                                   // the refusal is remembered for this model
        for i in [1, 2] {
            #expect(log.body(i)["text"] == nil)
            #expect((log.body(i)["instructions"] as? String)?.contains("Reply with JSON only") == true)
        }
    }

    @Test func aRejectedTokenIsRefreshedOnce() async throws {
        let log = RequestLog()
        let llm = client([(401, "{}", [:]), (200, sse("ok"), [:])], log: log)
        #expect(try await llm.respond(request) == "ok")
        #expect(log.all.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer at1", "Bearer at2"])
    }

    @Test func rejectedTwiceMeansSignedOut() async {
        let llm = client([(401, "{}", [:]), (401, "{}", [:])], log: RequestLog())
        await #expect(throws: LLMError.signedOut) { try await llm.respond(request) }
    }

    @Test func otherFailuresAreUnavailable() async {
        let llm = client([(503, "busy", [:])], log: RequestLog())
        await #expect(throws: LLMError.self) { try await llm.respond(request) }
        do { _ = try await llm.respond(request); Issue.record("expected a throw") }
        catch let error as LLMError { if case .unavailable = error {} else { Issue.record("got \(error)") } }
        catch { Issue.record("got \(error)") }
    }
}
