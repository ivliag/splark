import Foundation
import SplarkKit

func chatgptLoginCommand() async throws {
    let creds = try await ChatGPTSession(store: store).signIn(open: openInBrowser)
    print("""
    Signed in as \(creds.email ?? "?").
      client_id: \(creds.clientId) · can use ChatGPT plan: \(creds.canUsePlan)
      access token expires: \(creds.expiresAt.formatted()) · refresh token: \(creds.refreshToken == nil ? "none" : "present")
    """)
}

/// Lists the plan's models and sends one triage-shaped request with a JSON schema.
func chatgptProbeCommand() async throws {
    let llm = ChatGPTLLMClient(session: ChatGPTSession(store: store), chosenModel: option("--model"))
    let models = try await llm.models()
    print("models (\(models.count)): \(models.joined(separator: ", ")); triage uses \(ChatGPTLLMClient.pickModel(available: models, chosen: option("--model")) ?? "none")")
    let started = Date()
    let text = try await llm.respond(LLMRequest(
        instructions: "Classify the Slack message for the reader. Reply with JSON only.",
        input: "DM from Marta Ruiz: can you approve the rollback now? checkout is failing for EU cards",
        schemaName: "probe",
        schemaJSON: #"{"type":"object","additionalProperties":false,"required":["level","lead"],"properties":{"level":{"type":"string","enum":["action","question","fyi"]},"lead":{"type":"string"}}}"#))
    print("answered in \(String(format: "%.1f", Date().timeIntervalSince(started))) s: \(text)")
}
