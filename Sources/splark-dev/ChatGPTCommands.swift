import Foundation
import SplarkKit

func chatgptLoginCommand() async throws {
    var prior: ChatGPTCredentials?
    if let json = try store.read(ChatGPTAuth.secretKey) { prior = try? JSONDecoder().decode(ChatGPTCredentials.self, from: Data(json.utf8)) }
    let hostId = prior?.hostId ?? ChatGPTAuth.newHostId()
    let server = try LoopbackServer(port: 0, path: "/callback", ipv4Only: true)
    let pkce = PKCE.random(), state = PKCE.randomURLSafeString(byteCount: 16), nonce = PKCE.randomURLSafeString(byteCount: 16)
    let url = ChatGPTAuth.authorizeURL(clientId: prior?.clientId, hostId: hostId, port: server.port, state: state, nonce: nonce, pkce: pkce, loginHint: prior?.email)
    print("Opening ChatGPT sign-in (port \(server.port))…\n  \(url.absoluteString)")
    openInBrowser(url)
    let callback = try await server.waitForCallback()
    print("callback keys: \(callback.query.keys.sorted())")
    if let error = callback.query["error"] { fail("OpenAI returned \(error): \(callback.query["error_description"] ?? "")") }
    let creds = try await ChatGPTAuth().exchange(callback: callback.query, expectedState: state, pkce: pkce, port: server.port, hostId: hostId, priorClientId: prior?.clientId)
    let json = String(decoding: try JSONEncoder().encode(creds), as: UTF8.self)
    try store.write(json, for: ChatGPTAuth.secretKey)
    print("""
    Signed in as \(creds.email ?? "?") (sub \(creds.subject ?? "?")).
      client_id: \(creds.clientId)
      can use ChatGPT plan: \(creds.canUsePlan) · scopes: \(creds.scopes.joined(separator: " "))
      access token expires: \(creds.expiresAt.formatted()) · refresh token: \(creds.refreshToken == nil ? "none" : "present")
    """)
}

func chatgptProbeCommand() async throws {
    guard let json = try store.read(ChatGPTAuth.secretKey) else { fail("not signed in; run chatgpt-login first") }
    var creds = try JSONDecoder().decode(ChatGPTCredentials.self, from: Data(json.utf8))
    if creds.needsRefresh(now: Date()) {
        creds = try await ChatGPTAuth().refresh(creds)
        try store.write(String(decoding: try JSONEncoder().encode(creds), as: UTF8.self), for: ChatGPTAuth.secretKey)
        print("refreshed access token")
    }
    let client = OpenAIClient()
    if args.contains("--raw-models") {
        var request = URLRequest(url: OpenAIClient.baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        print("GET /v1/models → HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        print(String(decoding: data, as: UTF8.self))
        return
    }
    let models = try await client.listModels(accessToken: creds.accessToken)
    print("models (\(models.count)): \(models.joined(separator: ", "))")
    guard let model = option("--model") ?? models.first(where: { $0.contains("nano") }) ?? models.first(where: { $0.contains("mini") }) ?? models.first else { fail("no models") }
    let schema: [String: Any] = [
        "type": "object", "additionalProperties": false, "required": ["level", "lead"],
        "properties": ["level": ["type": "string", "enum": ["action", "question", "fyi"]], "lead": ["type": "string"]],
    ]
    let input = "DM from Marta Ruiz: can you approve the rollback now? checkout is failing for EU cards"
    let instructions = "Classify the Slack message for the reader. Reply with JSON only."
    for (label, useSchema) in [("json_schema", true), ("plain", false)] {
        let t = Date()
        do {
            let text = try await client.respond(accessToken: creds.accessToken, model: model, instructions: instructions, input: input,
                                                schemaName: useSchema ? "triage" : nil, schema: useSchema ? schema : nil)
            print("\(label) with \(model) in \(String(format: "%.1f", Date().timeIntervalSince(t))) s: \(text)")
        } catch {
            print("\(label) with \(model) FAILED: \(error)")
        }
    }
}
