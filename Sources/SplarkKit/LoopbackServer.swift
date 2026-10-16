import Foundation
import Network

/// One-shot HTTP listener on the loopback interface that captures a single OAuth redirect.
public final class LoopbackServer: @unchecked Sendable {
    public struct Callback: Sendable, Equatable {
        public let path: String
        public let query: [String: String]
    }

    public enum ServerError: Error, Equatable { case portUnavailable(UInt16), timedOut, cancelled }

    public let port: UInt16
    private let path: String
    private let successHTML: String
    private let queue = DispatchQueue(label: "splark.loopback")
    private var listeners: [NWListener] = []
    private var continuation: CheckedContinuation<Callback, Error>?
    private var received: Callback?
    private var finished = false

    /// Binds 127.0.0.1 and, unless `ipv4Only`, ::1 on `port` (0 = pick a free port).
    public init(port: UInt16, path: String, ipv4Only: Bool = false, successHTML: String = LoopbackServer.defaultHTML) throws {
        self.path = path
        self.successHTML = successHTML
        let v4 = try Self.makeListener(host: "127.0.0.1", port: port)
        let actualPort = try Self.start(v4, on: queue)
        self.port = actualPort
        listeners = [v4]
        if !ipv4Only, let v6 = try? Self.makeListener(host: "::1", port: actualPort), (try? Self.start(v6, on: queue)) != nil {
            listeners.append(v6)
        }
        for listener in listeners {
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        }
    }

    public static let defaultHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>Splark</title></head>
    <body style="font-family:-apple-system,sans-serif;color:#3a3a3e;text-align:center;padding-top:80px">
    <h2 style="font-weight:600">You're connected.</h2><p>You can close this tab and go back to Splark.</p></body></html>
    """

    /// Waits for the first request whose path matches, then stops listening.
    public func waitForCallback(timeout: Duration = .seconds(600)) async throws -> Callback {
        try await withThrowingTaskGroup(of: Callback.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    self.queue.async {
                        if let received = self.received { cont.resume(returning: received) }
                        else if self.finished { cont.resume(throwing: ServerError.cancelled) }
                        else { self.continuation = cont }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ServerError.timedOut
            }
            defer { group.cancelAll(); self.stop() }
            return try await group.next()!
        }
    }

    public func stop() {
        queue.async {
            guard !self.finished else { return }
            self.finished = true
            self.listeners.forEach { $0.cancel() }
            self.continuation?.resume(throwing: ServerError.cancelled)
            self.continuation = nil
        }
    }

    private static func makeListener(host: String, port: UInt16) throws -> NWListener {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .any)
        return try NWListener(using: params)
    }

    private static func start(_ listener: NWListener, on queue: DispatchQueue) throws -> UInt16 {
        let ready = DispatchSemaphore(value: 0)
        let failure = LockedBox<Error?>(nil)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let error): failure.value = error; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { $0.cancel() }
        listener.start(queue: queue)
        if ready.wait(timeout: .now() + 2) == .timedOut || failure.value != nil || listener.port == nil {
            listener.cancel()
            throw ServerError.portUnavailable(listener.port?.rawValue ?? 0)
        }
        return listener.port!.rawValue
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(connection, buffer: Data())
    }

    /// Reads until the end of the HTTP head (a blank line), however the bytes are split across packets.
    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            let headComplete = buffer.range(of: Data("\r\n\r\n".utf8)) != nil
            if !headComplete, !isComplete, error == nil, buffer.count < 65_536 {
                self.receiveHead(connection, buffer: buffer)
                return
            }
            self.respond(connection, head: String(decoding: buffer, as: UTF8.self))
        }
    }

    private func respond(_ connection: NWConnection, head: String) {
        let callback = Self.parse(requestHead: head)
        let matched = callback?.path == path
        let body = matched ? successHTML : "Not found"
        let status = matched ? "200 OK" : "404 Not Found"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        if matched, let callback, !finished {
            finished = true
            received = callback
            listeners.forEach { $0.cancel() }
            continuation?.resume(returning: callback)
            continuation = nil
        }
    }

    /// Parses `GET /path?a=1&b=2 HTTP/1.1` into path and decoded query items.
    static func parse(requestHead: String) -> Callback? {
        guard let line = requestHead.split(separator: "\r\n", omittingEmptySubsequences: false).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", let components = URLComponents(string: String(parts[1])) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return Callback(path: components.path, query: query)
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value
    init(_ value: Value) { _value = value }
    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
