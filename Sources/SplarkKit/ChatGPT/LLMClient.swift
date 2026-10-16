import Foundation

/// The AI behind triage (spec §5.2). v1 has one: the user's ChatGPT plan. API-key providers come later.
public protocol LLMClient: Sendable {
    func respond(_ request: LLMRequest) async throws -> String
}

public struct LLMRequest: Sendable, Equatable {
    public let instructions: String
    public let input: String
    public let schemaName: String
    public let schemaJSON: String   // a JSON Schema, sent as a strict `text.format`

    public init(instructions: String, input: String, schemaName: String, schemaJSON: String) {
        self.instructions = instructions
        self.input = input
        self.schemaName = schemaName
        self.schemaJSON = schemaJSON
    }
}

public enum LLMError: Error, Equatable {
    case signedOut                    // no credentials, or the refresh was refused: "sign in again"
    case notEligible                  // the plan doesn't grant chatgpt.tokens.use.direct
    case usageLimited(until: Date)    // "Summaries paused until 15:40"
    case unavailable(String)          // network, server errors, a broken stream
}

/// Sends triage requests with the user's ChatGPT plan (spec §7.2).
public actor ChatGPTLLMClient: LLMClient {
    /// The default triage model: the first of these the plan offers, else the first listed (spec §7.2).
    public static let preferredModels = ["gpt-6-luna", "gpt-5.6-luna"]

    public static func pickModel(available: [String], chosen: String?) -> String? {
        if let chosen, available.contains(chosen) { return chosen }
        return preferredModels.first(where: available.contains) ?? available.first
    }

    private let session: ChatGPTSession
    private let openAI: OpenAIClient
    private let now: @Sendable () -> Date
    public private(set) var chosenModel: String?
    private var available: [String]?
    private var schemaRefused: Set<String> = []   // models that turned down `text.format` json_schema

    public init(session: ChatGPTSession, openAI: OpenAIClient = OpenAIClient(), chosenModel: String? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.openAI = openAI
        self.chosenModel = chosenModel
        self.now = now
    }

    public func setModel(_ model: String?) { chosenModel = model }

    /// The plan's models, fetched once.
    public func models() async throws -> [String] {
        if let available { return available }
        let list = try await openAI.listModels(accessToken: try await session.accessToken())
        available = list
        return list
    }

    public func respond(_ request: LLMRequest) async throws -> String {
        do {
            let token = try await session.accessToken()
            do { return try await send(request, token: token) }
            catch OpenAIError.http(401, _) { return try await send(request, token: try await session.refreshAfterRejection(of: token)) }
        } catch let error as LLMError {
            throw error
        } catch OpenAIError.http(401, _) {
            throw LLMError.signedOut
        } catch OpenAIError.http(403, _) {
            throw LLMError.notEligible
        } catch OpenAIError.rateLimited(let retryAfter, let body) {
            throw LLMError.usageLimited(until: now().addingTimeInterval(Self.resetDelay(body: body) ?? retryAfter ?? 1800))
        } catch {
            throw LLMError.unavailable("\(error)")
        }
    }

    private func send(_ request: LLMRequest, token: String) async throws -> String {
        guard let model = Self.pickModel(available: try await models(), chosen: chosenModel) else { throw LLMError.unavailable("no models") }
        if !schemaRefused.contains(model) {
            let schema = try JSONSerialization.jsonObject(with: Data(request.schemaJSON.utf8)) as? [String: Any]
            do {
                return try await openAI.respond(accessToken: token, model: model, instructions: request.instructions, input: request.input,
                                                schemaName: request.schemaName, schema: schema)
            } catch OpenAIError.http(400, let body) where body.contains("text.format") || body.contains("json_schema") {
                schemaRefused.insert(model)
            }
        }
        // Spec §7.2's fallback: ask for JSON in the instructions; the caller parses it strictly.
        return try await openAI.respond(accessToken: token, model: model,
                                        instructions: request.instructions + "\n\nReply with JSON only, matching this JSON Schema:\n" + request.schemaJSON,
                                        input: request.input)
    }

    /// `{"error":{"type":"usage_limit_reached","resets_in_seconds":600}}` → 600.
    static func resetDelay(body: String) -> TimeInterval? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        if let seconds = error["resets_in_seconds"] as? Double { return seconds }
        return nil
    }
}
