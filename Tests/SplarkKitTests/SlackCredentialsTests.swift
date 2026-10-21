import Foundation
import Testing
@testable import SplarkKit

@Suite struct SlackCredentialsTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func creds(expiresIn: TimeInterval? = 43200, refreshToken: String? = "xoxe-1-r1") -> SlackCredentials {
        SlackCredentials(teamId: "T1", userId: "U1", accessToken: "xoxe.xoxp-a1", refreshToken: refreshToken,
                         expiresAt: expiresIn.map { start.addingTimeInterval($0) }, clientId: "123.456")
    }

    @Test func roundTripsThroughTheStore() throws {
        let store = InMemorySecretStore()
        try creds().save(to: store)
        #expect(try store.read("slack.T1") != nil)
        #expect(try SlackCredentials.load(teamId: "T1", from: store) == creds())
        #expect(try SlackCredentials.load(teamId: "T2", from: store) == nil)
    }

    @Test func needsRefreshWithinThirtyMinutesOfExpiry() {
        #expect(creds(expiresIn: 1799).needsRefresh(now: start))
        #expect(!creds(expiresIn: 1801).needsRefresh(now: start))
        #expect(!creds(expiresIn: nil).needsRefresh(now: start))           // manual tokens don't expire
        #expect(!creds(expiresIn: 10, refreshToken: nil).needsRefresh(now: start))
    }

    @Test func neverPrintsTokens() {
        for text in ["\(creds())", String(reflecting: creds())] {
            #expect(!text.contains("xoxe.xoxp-a1") && !text.contains("xoxe-1-r1"))
        }
    }
}

@Suite struct SlackTokenManagerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func add(_ v: String) { lock.withLock { values.append(v) } }
        var all: [String] { lock.withLock { values } }
    }

    func creds(expiresIn: TimeInterval) -> SlackCredentials {
        SlackCredentials(teamId: "T1", userId: "U1", accessToken: "xoxe.xoxp-a1", refreshToken: "xoxe-1-r1",
                         expiresAt: start.addingTimeInterval(expiresIn), clientId: "123.456")
    }

    /// A store holding `credentials`, as it is once a workspace is connected.
    func connected(_ credentials: SlackCredentials) -> InMemorySecretStore {
        let store = InMemorySecretStore()
        try! credentials.save(to: store)
        return store
    }

    func refresh(_ token: String, _ refresh: String) -> SlackTokenRefresh {
        try! SlackClient.decoder.decode(SlackTokenRefresh.self, from: Data(#"{"access_token":"\#(token)","refresh_token":"\#(refresh)","expires_in":43200}"#.utf8))
    }

    @Test func returnsTheTokenWithoutRefreshingWhileFresh() async throws {
        let calls = Calls()
        let manager = SlackTokenManager(credentials: creds(expiresIn: 7200), store: InMemorySecretStore(),
                                        refresher: { _, r in calls.add(r); return refresh("x", "y") }, now: { start })
        #expect(try await manager.accessToken() == "xoxe.xoxp-a1")
        #expect(calls.all.isEmpty)
    }

    @Test func refreshesNearExpiryAndSavesBeforeReturning() async throws {
        let store = connected(creds(expiresIn: 600))
        let calls = Calls()
        let manager = SlackTokenManager(credentials: creds(expiresIn: 600), store: store,
                                        refresher: { client, r in calls.add("\(client) \(r)"); return refresh("xoxe.xoxp-a2", "xoxe-1-r2") }, now: { start })
        #expect(try await manager.accessToken() == "xoxe.xoxp-a2")
        #expect(calls.all == ["123.456 xoxe-1-r1"])
        let saved = try #require(try SlackCredentials.load(teamId: "T1", from: store))
        #expect(saved.accessToken == "xoxe.xoxp-a2" && saved.refreshToken == "xoxe-1-r2")
        #expect(saved.expiresAt == start.addingTimeInterval(43200))
        #expect(await manager.credentials == saved)
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let calls = Calls()
        let manager = SlackTokenManager(credentials: creds(expiresIn: 60), store: connected(creds(expiresIn: 60)), refresher: { _, r in
            calls.add(r)
            try await Task.sleep(for: .milliseconds(50))
            return refresh("xoxe.xoxp-a2", "xoxe-1-r2")
        }, now: { start })
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 { group.addTask { try await manager.accessToken() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(Set(tokens) == ["xoxe.xoxp-a2"])
        #expect(calls.all.count == 1)
    }

    /// A Keychain that can't be read or written for a while: locked, or refusing a new build of the app.
    final class FlakyStore: SecretStore, @unchecked Sendable {
        let inner: InMemorySecretStore
        private let lock = NSLock()
        private var _failing = false
        var failing: Bool { get { lock.withLock { _failing } } set { lock.withLock { _failing = newValue } } }
        init(_ inner: InMemorySecretStore) { self.inner = inner }
        func read(_ key: String) throws -> String? { if failing { throw CocoaError(.fileReadNoPermission) }; return try inner.read(key) }
        func write(_ value: String, for key: String) throws { if failing { throw CocoaError(.fileWriteNoPermission) }; try inner.write(value, for: key) }
        func delete(_ key: String) throws { try inner.delete(key) }
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ value: Date) { self.value = value }
        var now: Date { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
    }

    /// Slack hands out a new refresh token with each refresh and stops taking the old one. When the Keychain couldn't save
    /// the new tokens, they were dropped, and the next refresh, with the old token, was refused: the workspace stopped
    /// syncing until reconnected (live run). The new tokens stay in use and are saved at the next chance.
    @Test func newTokensSurviveAKeychainThatWontKeepThem() async throws {
        let store = FlakyStore(connected(creds(expiresIn: 60)))
        let clock = Clock(start)
        let manager = SlackTokenManager(credentials: creds(expiresIn: 60), store: store, refresher: { _, r in
            switch r {
            case "xoxe-1-r1": return refresh("xoxe.xoxp-a2", "xoxe-1-r2")
            case "xoxe-1-r2": return refresh("xoxe.xoxp-a3", "xoxe-1-r3")
            default: throw SlackError.api("invalid_refresh_token")   // used already
            }
        }, now: { clock.now })
        store.failing = true
        #expect(try await manager.accessToken() == "xoxe.xoxp-a2")
        store.failing = false
        #expect(try await manager.accessToken() == "xoxe.xoxp-a2")
        #expect(try SlackCredentials.load(teamId: "T1", from: store.inner)?.refreshToken == "xoxe-1-r2")   // saved at the next chance
        clock.now = start.addingTimeInterval(43200)
        store.failing = true
        #expect(try await manager.accessToken() == "xoxe.xoxp-a3")
    }

    @Test func aRefusedRefreshMeansReconnect() async {
        let manager = SlackTokenManager(credentials: creds(expiresIn: 60), store: InMemorySecretStore(),
                                        refresher: { _, _ in throw SlackError.api("invalid_refresh_token") }, now: { start })
        await #expect(throws: SlackError.refreshFailed("invalid_refresh_token")) { try await manager.accessToken() }
    }

    @Test func aSlackHiccupIsNotAReasonToReconnect() async {
        let manager = SlackTokenManager(credentials: creds(expiresIn: 60), store: connected(creds(expiresIn: 60)),
                                        refresher: { _, _ in throw SlackError.api("internal_error") }, now: { start })
        await #expect(throws: SlackError.api("internal_error")) { try await manager.accessToken() }
    }

    @Test func disconnectingDuringARefreshStaysDisconnected() async throws {
        let store = connected(creds(expiresIn: 60))
        let manager = SlackTokenManager(credentials: creds(expiresIn: 60), store: store, refresher: { _, _ in
            try store.delete("slack.T1")   // the user removed the workspace meanwhile
            return refresh("xoxe.xoxp-a2", "xoxe-1-r2")
        }, now: { start })
        await #expect(throws: SlackError.refreshFailed("disconnected")) { try await manager.accessToken() }
        #expect(try store.read("slack.T1") == nil)
    }

    @Test func reconnectingDuringARefreshKeepsTheNewTokens() async throws {
        let store = connected(creds(expiresIn: 60))
        var reconnected = creds(expiresIn: 43200)
        reconnected.accessToken = "xoxe.xoxp-new"
        reconnected.refreshToken = "xoxe-1-new"
        let fresh = reconnected
        let manager = SlackTokenManager(credentials: creds(expiresIn: 60), store: store, refresher: { _, _ in
            try fresh.save(to: store)
            return refresh("xoxe.xoxp-a2", "xoxe-1-r2")
        }, now: { start })
        #expect(try await manager.accessToken() == "xoxe.xoxp-new")
        #expect(try SlackCredentials.load(teamId: "T1", from: store) == fresh)
    }

    @Test func aRejectedTokenThatWasAlreadyReplacedIsNotRefreshedAgain() async throws {
        let calls = Calls()
        let manager = SlackTokenManager(credentials: creds(expiresIn: 7200), store: connected(creds(expiresIn: 7200)),
                                        refresher: { _, r in calls.add(r); return refresh("xoxe.xoxp-a2", "xoxe-1-r2") }, now: { start })
        #expect(try await manager.refreshAfterRejection(of: "xoxe.xoxp-a1") == "xoxe.xoxp-a2")
        #expect(try await manager.refreshAfterRejection(of: "xoxe.xoxp-a1") == "xoxe.xoxp-a2")
        #expect(calls.all.count == 1)
    }

    @Test func clientRefreshesOnceWhenSlackSaysTheTokenExpired() async throws {
        let stub = StubTransport(json: #"{"ok":false,"error":"token_expired"}"#, #"{"ok":true,"user_id":"U1","team_id":"T1"}"#)
        let manager = SlackTokenManager(credentials: creds(expiresIn: 7200), store: connected(creds(expiresIn: 7200)),
                                        refresher: { _, _ in refresh("xoxe.xoxp-a2", "xoxe-1-r2") }, now: { start })
        _ = try await SlackClient(tokens: manager, transport: stub, sleeper: RecordingSleeper()).authTest()
        #expect(stub.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer xoxe.xoxp-a1", "Bearer xoxe.xoxp-a2"])
    }

    @Test func manyCallsRejectedTogetherShareOneRefresh() async throws {
        /// Answers token_expired to the old token and ok to the new one, whatever the order of calls.
        final class ExpiringSlack: HTTPTransport, @unchecked Sendable {
            func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
                let old = request.value(forHTTPHeaderField: "Authorization") == "Bearer xoxe.xoxp-a1"
                let body = old ? #"{"ok":false,"error":"token_expired"}"# : #"{"ok":true,"user_id":"U1","team_id":"T1"}"#
                return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        let calls = Calls()
        let manager = SlackTokenManager(credentials: creds(expiresIn: 7200), store: connected(creds(expiresIn: 7200)), refresher: { _, r in
            calls.add(r)
            try await Task.sleep(for: .milliseconds(30))
            return refresh("xoxe.xoxp-a2", "xoxe-1-r2")
        }, now: { start })
        let client = SlackClient(tokens: manager, transport: ExpiringSlack(), sleeper: RecordingSleeper())
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = try await client.authTest() } }
            try await group.waitForAll()
        }
        #expect(calls.all.count == 1)
    }

    @Test func clientGivesUpWhenTheFreshTokenIsAlsoRejected() async {
        let expired = #"{"ok":false,"error":"token_expired"}"#
        let stub = StubTransport(json: expired, expired, expired)
        let manager = SlackTokenManager(credentials: creds(expiresIn: 7200), store: connected(creds(expiresIn: 7200)),
                                        refresher: { _, _ in refresh("xoxe.xoxp-a2", "xoxe-1-r2") }, now: { start })
        await #expect(throws: SlackError.api("token_expired")) {
            try await SlackClient(tokens: manager, transport: stub, sleeper: RecordingSleeper()).authTest()
        }
        #expect(stub.requests.count == 2)
    }
}
