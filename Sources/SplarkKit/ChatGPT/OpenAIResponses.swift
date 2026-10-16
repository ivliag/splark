import Foundation

/// Accumulates a streamed Responses API reply (server-sent events).
public struct ResponseStreamParser: Sendable {
    public private(set) var text = ""
    public private(set) var completed = false
    public private(set) var failure: String?
    private var buffer = ""

    public init() {}

    /// Feed raw bytes as they arrive (any chunking).
    public mutating func feed(_ chunk: String) {
        buffer += chunk
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            buffer.removeSubrange(..<range.upperBound)
            handle(line: line)
        }
    }

    private mutating func handle(line: String) {
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch type {
        case "response.output_text.delta": text += event["delta"] as? String ?? ""
        case "response.completed": completed = true
        case "response.failed", "error":
            let error = (event["response"] as? [String: Any])?["error"] as? [String: Any] ?? event["error"] as? [String: Any] ?? event
            failure = (error["message"] as? String) ?? "\(error)"
        default: break
        }
    }
}

public enum OpenAIError: Error, Equatable { case http(Int, String), stream(String), incomplete }

/// Minimal client for the endpoints Splark uses with ChatGPT-plan tokens (spec §7.2).
public struct OpenAIClient: Sendable {
    public static let baseURL = URL(string: "https://api.openai.com/v1/")!
    private let transport: HTTPTransport
    private let streamer: @Sendable (URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse)

    public init(transport: HTTPTransport = URLSessionTransport(),
                streamer: @escaping @Sendable (URLRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) = { request in
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    return (bytes, response as! HTTPURLResponse)
                }) {
        self.transport = transport
        self.streamer = streamer
    }

    public func listModels(accessToken: String) async throws -> [String] {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else { throw OpenAIError.http(response.statusCode, String(decoding: data, as: UTF8.self)) }
        // API keys get {"data":[{"id":…}]}; ChatGPT-plan tokens get {"models":[{"slug":…,"visibility":…,"supported_in_api":…}]}.
        struct List: Decodable {
            struct APIModel: Decodable { let id: String }
            struct PlanModel: Decodable { let slug: String; let visibility: String?; let supported_in_api: Bool? }
            let data: [APIModel]?
            let models: [PlanModel]?
        }
        let list = try JSONDecoder().decode(List.self, from: data)
        let ids = list.data?.map(\.id)
            ?? list.models?.filter { $0.visibility != "hide" && $0.supported_in_api != false }.map(\.slug)
            ?? []
        return ids.sorted()
    }

    /// The request body: always `stream: true`, `store: false`, instructions (never a system message).
    public static func responsesBody(model: String, instructions: String, input: String, schemaName: String?, schema: [String: Any]?) -> Data {
        // Plan tokens reject a bare string ("Input must be a list"): send one user message.
        let message: [String: Any] = ["type": "message", "role": "user", "content": [["type": "input_text", "text": input]]]
        var body: [String: Any] = ["model": model, "instructions": instructions, "input": [message], "stream": true, "store": false]
        if let schemaName, let schema {
            body["text"] = ["format": ["type": "json_schema", "name": schemaName, "schema": schema, "strict": true]]
        }
        return try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    public func respond(accessToken: String, model: String, instructions: String, input: String,
                        schemaName: String? = nil, schema: [String: Any]? = nil) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = Self.responsesBody(model: model, instructions: instructions, input: input, schemaName: schemaName, schema: schema)
        let (bytes, response) = try await streamer(request)
        var parser = ResponseStreamParser()
        var raw = ""
        for try await line in bytes.lines {
            raw += line + "\n"
            parser.feed(line + "\n")
        }
        guard response.statusCode == 200 else { throw OpenAIError.http(response.statusCode, String(raw.prefix(2000))) }
        if let failure = parser.failure { throw OpenAIError.stream(failure) }
        guard parser.completed else { throw OpenAIError.incomplete }
        return parser.text
    }
}
