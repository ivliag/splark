import Foundation
@testable import SplarkKit

/// Replays queued responses in order and records every request it receives.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Reply { let status: Int; let body: String; let headers: [String: String] }
    private let lock = NSLock()
    private var replies: [Reply]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [Reply]) { self.replies = replies }
    convenience init(json bodies: String...) { self.init(bodies.map { Reply(status: 200, body: $0, headers: [:]) }) }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply = lock.withLock {
            requests.append(request)
            return replies.isEmpty ? Reply(status: 500, body: "{}", headers: [:]) : replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }

    func formBody(_ index: Int) -> [String: String] {
        let body = String(decoding: requests[index].httpBody ?? Data(), as: UTF8.self)
        var out: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            out[kv[0]] = kv.count > 1 ? kv[1].removingPercentEncoding : ""
        }
        return out
    }
}

final class RecordingSleeper: Sleeper, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var slept: [Double] = []
    func sleep(seconds: Double) async throws { lock.withLock { slept.append(seconds) } }
}

/// A clock tests can move by hand.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
