import Foundation

public enum SlackError: Error, Equatable, Sendable {
    case api(String)                         // {"ok": false, "error": "..."}
    case rateLimited(retryAfter: TimeInterval)
    case http(Int)
    case decoding(String)
}

private struct SlackEnvelope: Decodable { let ok: Bool; let error: String? }

/// Typed access to the Slack Web API: form-encoded POSTs, Bearer token, per-method rate limiting,
/// `Retry-After` handling (two retries), and `ok: false` mapped to `SlackError.api`.
public struct SlackClient: Sendable {
    public let token: String?
    private let transport: HTTPTransport
    private let limiter: RateLimiter
    private let sleeper: Sleeper
    private let baseURL: URL

    public init(token: String?, transport: HTTPTransport = URLSessionTransport(), limiter: RateLimiter = RateLimiter(),
                sleeper: Sleeper = TaskSleeper(), baseURL: URL = URL(string: "https://slack.com/api/")!) {
        self.token = token
        self.transport = transport
        self.limiter = limiter
        self.sleeper = sleeper
        self.baseURL = baseURL
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    public func call<Response: Decodable & Sendable>(_ method: String, tier: SlackTier, params: [String: String] = [:],
                                                    bearer: String? = nil, as: Response.Type = Response.self) async throws -> Response {
        let url = baseURL.appendingPathComponent(method)
        var attempt = 0
        while true {
            try await sleeper.sleep(seconds: await limiter.reserve(method, tier: tier))
            let (data, response) = try await transport.send(.form(url, params, bearer: bearer ?? token))
            if response.statusCode == 429 {
                let retryAfter = TimeInterval(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30
                await limiter.pause(method, retryAfter: retryAfter)
                attempt += 1
                if attempt > 2 { throw SlackError.rateLimited(retryAfter: retryAfter) }
                continue
            }
            guard response.statusCode == 200 else { throw SlackError.http(response.statusCode) }
            let envelope: SlackEnvelope
            do { envelope = try Self.decoder.decode(SlackEnvelope.self, from: data) }
            catch { throw SlackError.decoding("\(method): \(error)") }
            guard envelope.ok else { throw SlackError.api(envelope.error ?? "unknown_error") }
            do { return try Self.decoder.decode(Response.self, from: data) }
            catch { throw SlackError.decoding("\(method): \(error)") }
        }
    }
}
