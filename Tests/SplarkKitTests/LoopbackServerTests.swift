import Foundation
import Network
import Testing
@testable import SplarkKit

@Suite struct LoopbackServerTests {
    @Test(arguments: ["127.0.0.1", "localhost"])
    func capturesCallback(host: String) async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        let waiter = Task { try await server.waitForCallback(timeout: .seconds(5)) }
        let url = URL(string: "http://\(host):\(server.port)/callback?code=abc%20123&state=xyz")!
        let (data, response) = try await URLSession.shared.data(from: url)
        #expect((response as! HTTPURLResponse).statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("You're connected"))
        #expect(try await waiter.value.query == ["code": "abc 123", "state": "xyz"])
    }

    @Test func aCancelledSignInGetsACancelledPageNotASuccessPage() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        let waiter = Task { try await server.waitForCallback(timeout: .seconds(5)) }
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/callback?error=access_denied&state=s")!)
        let page = String(decoding: data, as: UTF8.self)
        #expect(page.contains("cancelled"))
        #expect(!page.contains("You're connected"))
        #expect(try await waiter.value.query["error"] == "access_denied")
    }

    @Test func keepsACallbackThatArrivesBeforeWaiting() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/callback?code=early&state=s")!)
        #expect(try await server.waitForCallback(timeout: .seconds(2)).query["code"] == "early")
    }

    @Test func capturesARequestSplitAcrossPackets() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        let waiter = Task { try await server.waitForCallback(timeout: .seconds(5)) }
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: server.port)!, using: .tcp)
        connection.start(queue: .global())
        connection.send(content: Data("GET /callback?code=sp".utf8), completion: .contentProcessed { _ in })
        try await Task.sleep(for: .milliseconds(150))
        connection.send(content: Data("lit&state=s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8), completion: .contentProcessed { _ in })
        #expect(try await waiter.value.query == ["code": "split", "state": "s"])
        connection.cancel()
    }

    @Test func ignoresOtherPathsAndTimesOut() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        let waiter = Task { try await server.waitForCallback(timeout: .milliseconds(800)) }
        let (_, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/favicon.ico")!)
        #expect((response as! HTTPURLResponse).statusCode == 404)
        await #expect(throws: LoopbackServer.ServerError.timedOut) { try await waiter.value }
    }

    @Test func refusesAPortInUse() throws {
        let first = try LoopbackServer(port: 0, path: "/callback")
        #expect(throws: LoopbackServer.ServerError.self) { try LoopbackServer(port: first.port, path: "/callback") }
        first.stop()
    }

    @Test func parsesRequestLine() {
        #expect(LoopbackServer.parse(requestHead: "GET /slack/callback?code=a&state=b HTTP/1.1\r\nHost: x\r\n\r\n")
                == .init(path: "/slack/callback", query: ["code": "a", "state": "b"]))
        #expect(LoopbackServer.parse(requestHead: "POST /x HTTP/1.1\r\n\r\n") == nil)
    }
}

@Suite struct PKCETests {
    @Test func matchesRFC7636Vector() {
        #expect(PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk").challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func randomVerifierIs43URLSafeCharacters() {
        let v = PKCE.random().verifier
        #expect(v.count == 43)
        #expect(v.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(PKCE.random() != PKCE.random())
    }
}

@Suite struct LoopbackServerSafetyTests {
    @Test func aCallbackWithTheWrongStateIsTurnedAwayAndTheWaitGoesOn() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback", expectedState: "good")
        let waiter = Task { try await server.waitForCallback(timeout: .seconds(5)) }
        let (_, stray) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/callback?code=evil&state=bad")!)
        #expect((stray as! HTTPURLResponse).statusCode == 400)
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/callback?code=real&state=good")!)
        #expect(try await waiter.value.query["code"] == "real")
    }

    @Test func aSecondWaiterFailsInsteadOfHanging() async throws {
        let server = try LoopbackServer(port: 0, path: "/callback")
        let first = Task { try await server.waitForCallback(timeout: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: LoopbackServer.ServerError.alreadyWaiting) { try await server.waitForCallback(timeout: .seconds(5)) }
        _ = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(server.port)/callback?code=c&state=s")!)
        #expect(try await first.value.query["code"] == "c")
    }

    @Test func droppingTheServerStopsListening() async throws {
        var port: UInt16 = 0
        do { port = try LoopbackServer(port: 0, path: "/callback").port }
        var refused = false
        for _ in 0..<20 where !refused {
            do {
                _ = try await URLSession.shared.data(for: URLRequest(url: URL(string: "http://127.0.0.1:\(port)/callback")!, timeoutInterval: 1))
            } catch let error as URLError where error.code == .cannotConnectToHost {
                refused = true   // nothing listens there any more
            } catch {}           // a timeout means something still holds the port
            if !refused { try await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(refused)
    }
}
