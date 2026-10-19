import AppKit
import SplarkKit
import SwiftUI

/// The real setup services: WorkspaceSetup for Slack, the engine for workspaces and ChatGPT, the browser, and login items.
@MainActor public final class LiveSetupServices: SetupServices {
    private let engine: SplarkEngine
    private let setup: WorkspaceSetup
    private let loginItem: LoginItemControlling
    private let onFinish: () -> Void

    public init(engine: SplarkEngine, loginItem: LoginItemControlling, onFinish: @escaping () -> Void) {
        self.engine = engine
        self.setup = WorkspaceSetup(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
        self.loginItem = loginItem
        self.onFinish = onFinish
    }

    public func createApp(configToken: String) async throws -> SlackAppRegistration { try await setup.createApp(configToken: configToken) }
    public func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection { try await setup.authorize(app) }
    public func connect(userToken: String) async throws -> SlackConnection { try await setup.connect(userToken: userToken) }
    public func added(_ connection: SlackConnection) async throws { try await engine.connect(connection) }
    public func waitingForApproval(_ app: SlackAppRegistration) async { await engine.addPendingApp(app) }

    public func signInToChatGPT() async throws -> ChatGPTAccount {
        _ = try await engine.signInToChatGPT(open: { url in Task { @MainActor in NSWorkspace.shared.open(url) } })
        return await engine.chatGPTAccount() ?? ChatGPTAccount(email: nil, canUsePlan: false)
    }

    public func open(_ url: URL) { NSWorkspace.shared.open(url) }

    public func setOpenAtLogin(_ on: Bool) {
        try? loginItem.setEnabled(on)
        Task { await engine.updateSettings { $0.openAtLogin = on } }
    }

    public func setShowCount(_ on: Bool) { Task { await engine.updateSettings { $0.showCount = on } } }

    public func finish() { onFinish() }
}

/// The setup window: 560 pt wide, with the step sparks in its transparent title bar. It grows with its content.
@MainActor public final class SetupWindowController: FittedWindow {
    private let model: SetupModel

    public init(model: SetupModel) {
        self.model = model
        super.init(rootView: SetupView(model: model), size: NSSize(width: 560, height: 520), title: "Splark")
    }

    /// A closed window stops waiting for Allow, so the app's redirect port is free for the next try.
    override public func windowWillClose(_ notification: Notification) {
        model.cancel()
        super.windowWillClose(notification)
    }
}
