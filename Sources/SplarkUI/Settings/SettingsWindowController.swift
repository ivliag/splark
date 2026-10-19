import AppKit
import SplarkKit
import SwiftUI

/// The real Settings services: the engine, WorkspaceSetup for Allow and pasted tokens, login items and the browser.
@MainActor public final class LiveSettingsServices: SettingsServices {
    private let engine: SplarkEngine
    private let setup: WorkspaceSetup
    private let loginItem: LoginItemControlling
    private let onAddWorkspace: () -> Void

    public init(engine: SplarkEngine, loginItem: LoginItemControlling, onAddWorkspace: @escaping () -> Void) {
        self.engine = engine
        self.setup = WorkspaceSetup(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
        self.loginItem = loginItem
        self.onAddWorkspace = onAddWorkspace
    }

    public var workspaces: [Workspace] { engine.workspaces }
    public var pendingApps: [SlackAppRegistration] { engine.pendingApps }
    public var syncStatus: [String: SyncStatus] { engine.syncStatus }
    public var badge: SlackBadge? { engine.badge }

    /// "Open at login" as macOS has it: the user may have changed it in System Settings.
    public var settings: SavedState.Settings {
        var settings = engine.settings
        settings.openAtLogin = loginItem.isEnabled
        return settings
    }

    public func channels(teamId: String) async -> [ChannelOption] { await engine.channels(teamId: teamId) }
    public func excludedChannels(teamId: String) -> Set<String> { engine.excludedChannels(teamId: teamId) }
    public func setExcluded(_ channels: Set<String>, teamId: String) async { await engine.setExcluded(channels, teamId: teamId) }

    public func reconnect(teamId: String) async throws {
        guard let app = engine.registration(for: teamId) else { throw ReconnectError.noSavedSignIn }
        try await engine.connect(try await setup.authorize(app))
    }

    public func finishConnecting(_ app: SlackAppRegistration) async throws {
        let connection = try await setup.authorize(app)
        try await engine.connect(connection)
        await engine.removePendingApp(app)
    }

    public func connect(userToken: String) async throws -> SlackConnection { try await setup.connect(userToken: userToken) }
    public func added(_ connection: SlackConnection) async throws { try await engine.connect(connection) }
    public func remove(teamId: String) async throws { try await engine.disconnect(teamId: teamId) }
    public func removePending(_ app: SlackAppRegistration) async { await engine.removePendingApp(app) }
    public func addWorkspace() { onAddWorkspace() }

    public func chatGPTAccount() async -> ChatGPTAccount? { await engine.chatGPTAccount() }
    public func models() async -> [String] { (try? await engine.availableModels()) ?? [] }
    public func setModel(_ model: String?) async { await engine.setModel(model) }
    public func signInToChatGPT() async throws {
        _ = try await engine.signInToChatGPT(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
    }
    public func signOutOfChatGPT() async throws { try await engine.signOutOfChatGPT() }
    public func setSummariesPaused(_ paused: Bool) async { await engine.setSummariesPaused(paused) }

    public func setOpenAtLogin(_ on: Bool) throws {
        try loginItem.setEnabled(on)
        Task { await engine.updateSettings { $0.openAtLogin = on } }
    }

    public func setShowCount(_ on: Bool) async { await engine.updateSettings { $0.showCount = on } }
    public func reset() async throws { try await engine.reset() }
    public func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// The Settings window: 520 pt wide, the section tabs in its transparent title bar. It fits each section's height.
@MainActor public final class SettingsWindowController: FittedWindow {
    private let model: SettingsModel

    public init(model: SettingsModel) {
        self.model = model
        super.init(rootView: SettingsView(model: model), size: NSSize(width: 520, height: 360), title: "Splark Settings")
    }

    /// Shows a section, reading the ChatGPT account afresh.
    public func show(_ section: SettingsModel.Section) {
        model.section = section
        show()
        Task { await model.load() }
    }

    /// A closed window stops waiting for Allow, so the app's redirect port is free for the next try.
    override public func windowWillClose(_ notification: Notification) {
        model.cancel()
        super.windowWillClose(notification)
    }
}
