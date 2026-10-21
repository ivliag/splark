import Foundation

/// Everything Splark keeps on disk (spec §8): IDs, names and settings. Never tokens, never message text.
public struct SavedState: Codable, Sendable, Equatable {
    public struct Settings: Codable, Sendable, Equatable {
        public var openAtLogin = true
        public var showCount = true
        public var summariesPaused = false
        public var model: String?   // nil: the recommended default

        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            openAtLogin = try c.decodeIfPresent(Bool.self, forKey: .openAtLogin) ?? true
            showCount = try c.decodeIfPresent(Bool.self, forKey: .showCount) ?? true
            summariesPaused = try c.decodeIfPresent(Bool.self, forKey: .summariesPaused) ?? false
            model = try c.decodeIfPresent(String.self, forKey: .model)
        }
    }

    public var version = 1
    public var workspaces: [Workspace] = []                          // in the order they were connected
    public var pendingApps: [SlackAppRegistration] = []              // created, still waiting for Allow
    public var excludedChannels: [String: [String]] = [:]            // team ID → channel IDs
    public var settings = Settings()
    public var sync: [String: SyncMemory] = [:]                      // team ID → threads and sweep position
    public var userNames: [String: [String: UserDirectory.Entry]] = [:]   // team ID → user ID → name

    public init() {}

    /// Fields missing from an older file take their defaults; unknown ones are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        workspaces = try c.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? []
        pendingApps = try c.decodeIfPresent([SlackAppRegistration].self, forKey: .pendingApps) ?? []
        excludedChannels = try c.decodeIfPresent([String: [String]].self, forKey: .excludedChannels) ?? [:]
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        sync = try c.decodeIfPresent([String: SyncMemory].self, forKey: .sync) ?? [:]
        userNames = try c.decodeIfPresent([String: [String: UserDirectory.Entry]].self, forKey: .userNames) ?? [:]
    }
}

/// Reads and writes `~/Library/Application Support/Splark/state.json`.
public struct StateStore: Sendable {
    public let url: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Splark", isDirectory: true).appendingPathComponent("state.json")
    }

    public init(url: URL = StateStore.defaultURL) { self.url = url }

    /// A missing file is a fresh start. A damaged one is moved to `state.json.broken` and Splark starts fresh.
    public func load() -> SavedState {
        guard let data = try? Data(contentsOf: url) else { return SavedState() }
        if let state = try? JSONDecoder().decode(SavedState.self, from: data) { return state }
        let aside = url.appendingPathExtension("broken")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return SavedState()
    }

    /// Reset Splark. A missing file is fine.
    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Atomic, and readable only by the user.
    public func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
