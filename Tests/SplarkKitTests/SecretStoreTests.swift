import Foundation
import Testing
@testable import SplarkKit

@Suite struct SecretStoreTests {
    @Test func inMemoryRoundTrip() throws {
        let store = InMemorySecretStore()
        #expect(try store.read("a") == nil)
        try store.write("1", for: "a")
        try store.write("2", for: "a")
        #expect(try store.read("a") == "2")
        try store.delete("a")
        try store.delete("a")
        #expect(try store.read("a") == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil, "CI runners have no unlocked login keychain"))
    func keychainRoundTrip() throws {
        let store = KeychainStore(service: "dev.splark.tests.\(UUID().uuidString)")
        defer { try? store.delete("token") }
        #expect(try store.read("token") == nil)
        try store.write("xoxp-1", for: "token")
        try store.write("xoxp-2", for: "token")
        #expect(try store.read("token") == "xoxp-2")
        try store.delete("token")
        #expect(try store.read("token") == nil)
    }
}
