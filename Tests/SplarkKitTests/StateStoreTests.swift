import Foundation
import Testing
@testable import SplarkKit

@Suite struct StateStoreTests {
    func tempStore() -> StateStore {
        StateStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("splark-\(UUID().uuidString)/state.json"))
    }

    var sample: SavedState {
        var state = SavedState()
        state.workspaces = [lumen, community]
        state.pendingApps = [SlackAppRegistration(appId: "A9", clientId: "1.2", redirectPort: 53683)]
        state.excludedChannels = ["T1": ["C9"]]
        state.settings.showCount = false
        state.settings.model = "gpt-5.6-luna"
        var memory = SyncMemory()
        memory.threads.watch(channelId: "C1", threadTs: "1.0", seenThrough: "2.0", activity: Date(timeIntervalSince1970: 1_800_000_000), now: Date(timeIntervalSince1970: 1_800_000_000))
        memory.sweptThrough = "3.0"
        state.sync = ["T1": memory]
        state.userNames = ["T1": ["U2": .init(name: "Marta Ruiz", fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))]]
        return state
    }

    @Test func roundTrips() throws {
        let store = tempStore()
        try store.save(sample)
        #expect(store.load() == sample)
    }

    @Test func noFileMeansAFreshStart() {
        let state = tempStore().load()
        #expect(state == SavedState())
        #expect(state.settings.openAtLogin && state.settings.showCount && !state.settings.summariesPaused)
    }

    @Test func aDamagedFileIsSetAsideNotLost() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: store.url)
        #expect(store.load() == SavedState())
        #expect(FileManager.default.fileExists(atPath: store.url.appendingPathExtension("broken").path))
    }

    @Test func missingFieldsTakeTheirDefaults() throws {
        let store = tempStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":1,"settings":{"showCount":false},"futureField":42}"#.utf8).write(to: store.url)
        let state = store.load()
        #expect(!state.settings.showCount && state.settings.openAtLogin && state.workspaces.isEmpty)
    }

    @Test func onlyTheUserCanReadIt() throws {
        let store = tempStore()
        try store.save(sample)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }

    @Test func holdsNoSecretsOrMessageText() throws {
        let store = tempStore()
        try store.save(sample)
        let json = try String(contentsOf: store.url, encoding: .utf8)
        #expect(Set(try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]).keys)
                == ["version", "workspaces", "pendingApps", "excludedChannels", "settings", "sync", "userNames"])
        #expect(!json.contains("xox"))
    }
}
