import Foundation
import Observation
import SplarkKit

/// What Settings needs from outside: the engine, Slack's Allow, ChatGPT, login items and the browser.
/// `LiveSettingsServices` is the real one; tests use a fake.
@MainActor public protocol SettingsServices: AnyObject {
    var workspaces: [Workspace] { get }
    var pendingApps: [SlackAppRegistration] { get }
    var syncStatus: [String: SyncStatus] { get }
    var badge: SlackBadge? { get }
    var settings: SavedState.Settings { get }
    func channels(teamId: String) async -> [ChannelOption]
    func excludedChannels(teamId: String) -> Set<String>
    func setExcluded(_ channels: Set<String>, teamId: String) async
    func reconnect(teamId: String) async throws
    func finishConnecting(_ app: SlackAppRegistration) async throws
    func connect(userToken: String) async throws -> SlackConnection
    func added(_ connection: SlackConnection) async throws
    func remove(teamId: String) async throws
    func removePending(_ app: SlackAppRegistration) async
    func addWorkspace()
    func chatGPTAccount() async -> ChatGPTAccount?
    func models() async -> [String]
    func setModel(_ model: String?) async
    func signInToChatGPT() async throws
    func signOutOfChatGPT() async throws
    func setSummariesPaused(_ paused: Bool) async
    func setOpenAtLogin(_ on: Bool) throws
    func setShowCount(_ on: Bool) async
    func reset() async throws
    func open(_ url: URL)
}

/// Reconnect needs the workspace's client ID, which only the Keychain has.
public enum ReconnectError: Error, Equatable { case noSavedSignIn }

/// A line in Settings → Workspaces: a connected workspace, or an app still waiting for an admin.
public struct WorkspaceRow: Identifiable, Equatable {
    public enum Action: Equatable, Sendable {
        case reconnect, pasteNewToken, finishConnecting

        public var title: String {
            switch self {
            case .reconnect: "Reconnect"
            case .pasteNewToken: "Paste new token"
            case .finishConnecting: "Finish connecting"
            }
        }
    }

    public let id: String          // the team ID, or the pending app's client ID
    public let name: String
    public let status: WorkspaceStatusText
    public let action: Action?     // the button the row needs, if any
    let pending: SlackAppRegistration?

    public var canExcludeChannels: Bool { pending == nil }
}

/// The excluded-channels sheet: every channel, a search, and checkmarks for the excluded ones.
public struct ChannelPicker: Equatable {
    public let teamId: String
    public let name: String
    public let channels: [ChannelOption]
    public var excluded: Set<String>
    public var search = ""

    public var shown: [ChannelOption] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? channels : channels.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
}

/// Settings (spec §4.5): workspaces, ChatGPT, general switches and about.
@MainActor @Observable public final class SettingsModel {
    public enum Section: String, CaseIterable { case workspaces = "Workspaces", chatgpt = "ChatGPT", general = "General", about = "About" }

    public var section: Section = .workspaces
    public private(set) var message: String?           // the last thing that went wrong, shown at the top
    public private(set) var working: String?           // the row waiting for Allow
    public private(set) var pasting: String?           // the row showing a token field
    public var newToken = ""
    public private(set) var removal: WorkspaceRow?
    public var channelPicker: ChannelPicker?
    public private(set) var confirmingReset = false

    public private(set) var account: ChatGPTAccount?
    public private(set) var models: [String] = []
    public private(set) var signingIn = false

    // As the engine has them now, so a pause from the menu shows here too.
    public var openAtLogin: Bool { services.settings.openAtLogin }
    public var showCount: Bool { services.settings.showCount }
    public var summariesPaused: Bool { services.settings.summariesPaused }
    public var model: String? { services.settings.model }   // nil: the recommended default

    private let services: SettingsServices
    private let now: () -> Date
    private let onReset: () -> Void
    private var allowTask: Task<Void, Error>?   // Reconnect or Finish connecting, holding the app's redirect port

    public init(services: SettingsServices, now: @escaping () -> Date = Date.init, onReset: @escaping () -> Void = {}) {
        self.services = services
        self.now = now
        self.onReset = onReset
    }

    /// When the window opens: the ChatGPT account and its models.
    public func load() async {
        account = await services.chatGPTAccount()
        models = account == nil ? [] : await services.models()
    }

    // MARK: Workspaces

    public var workspaceRows: [WorkspaceRow] {
        let workspaces = services.workspaces.map { workspace in
            let sync = services.syncStatus[workspace.teamId]
            return WorkspaceRow(id: workspace.teamId, name: workspace.name,
                                status: Presenter.workspaceStatus(workspace, sync: sync, now: now()),
                                action: Self.action(workspace, sync: sync), pending: nil)
        }
        let pending = services.pendingApps.map { app in
            WorkspaceRow(id: app.clientId, name: "Slack workspace",
                         status: WorkspaceStatusText(title: "Waiting for approval", detail: "An admin needs to approve it"),
                         action: .finishConnecting, pending: app)
        }
        return workspaces + pending
    }

    private static func action(_ workspace: Workspace, sync: SyncStatus?) -> WorkspaceRow.Action? {
        let needed = sync?.problem?.stopsSync == true || sync?.missingScope == true
        guard needed else { return nil }
        return workspace.redirectPort == nil ? .pasteNewToken : .reconnect
    }

    public var badgeLine: String {
        services.badge == nil
            ? "Slack isn't open, or its Dock badge can't be read, so Splark checks every couple of minutes."
            : "Slack is open, so new messages show up within seconds."
    }

    public func perform(_ action: WorkspaceRow.Action, on row: WorkspaceRow) async {
        message = nil
        switch action {
        case .pasteNewToken:
            pasting = row.id
            newToken = ""
        case .reconnect, .finishConnecting:
            guard working == nil else { return }   // one Allow at a time: they would want the same port
            working = row.id
            let task = Task { [services] in
                if let app = row.pending { try await services.finishConnecting(app) } else { try await services.reconnect(teamId: row.id) }
            }
            allowTask = task
            defer {
                working = nil
                allowTask = nil
            }
            do {
                try await task.value
            } catch ReconnectError.noSavedSignIn {
                message = "Splark can't read \(row.name)'s saved sign-in from the Keychain. Remove it and add it again."
            } catch {
                if !task.isCancelled { message = SetupModel.message(for: error) }
            }
        }
    }

    /// A pasted token's workspace has no app to Allow again: a fresh token from the same workspace replaces it.
    public func savePastedToken() async {
        guard let teamId = pasting, let row = workspaceRows.first(where: { $0.id == teamId }) else { return }
        let token = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        message = nil
        do {
            let connection = try await services.connect(userToken: token)
            guard connection.workspace.teamId == teamId else {
                message = "That token is for \(connection.workspace.name), not \(row.name). Paste one made in \(row.name)."
                return
            }
            try await services.added(connection)
            pasting = nil
            newToken = ""
        } catch {
            message = SetupModel.message(for: error)
        }
    }

    /// Stops waiting for Allow, freeing the redirect port: the window closed, or the user clicked Cancel.
    public func cancel() {
        allowTask?.cancel()
    }

    public func cancelPasting() {
        pasting = nil
        newToken = ""
    }

    public func addWorkspace() { services.addWorkspace() }

    public func askToRemove(_ row: WorkspaceRow) { removal = row }
    public func cancelRemoval() { removal = nil }

    public var removalNote: String {
        guard let removal else { return "" }
        if removal.pending != nil {
            return "Splark forgets this app. To delete it from Slack too, open api.slack.com/apps, choose Splark, and click Delete App."
        }
        return "Splark forgets \(removal.name)'s token. To delete your private Splark app too, open api.slack.com/apps, choose Splark, and click Delete App."
    }

    public func confirmRemoval() async {
        guard let row = removal else { return }
        removal = nil
        do {
            if let app = row.pending { await services.removePending(app) } else { try await services.remove(teamId: row.id) }
        } catch {
            message = "Removed \(row.name), but macOS wouldn't delete its token from the Keychain."   // the engine removes it regardless
        }
    }

    public func openSlackApps() { services.open(URL(string: "https://api.slack.com/apps")!) }

    // MARK: Excluded channels

    public func editChannels(_ row: WorkspaceRow) async {
        guard row.canExcludeChannels else { return }
        let channels = await services.channels(teamId: row.id)
        channelPicker = ChannelPicker(teamId: row.id, name: row.name, channels: channels, excluded: services.excludedChannels(teamId: row.id))
    }

    public func toggleChannel(_ id: String) {
        guard var picker = channelPicker else { return }
        if picker.excluded.contains(id) { picker.excluded.remove(id) } else { picker.excluded.insert(id) }
        channelPicker = picker
    }

    public func saveChannels() async {
        guard let picker = channelPicker else { return }
        channelPicker = nil
        await services.setExcluded(picker.excluded, teamId: picker.teamId)
    }

    public func cancelChannels() { channelPicker = nil }

    // MARK: ChatGPT

    public var recommendedModel: String? { ChatGPTLLMClient.pickModel(available: models, chosen: nil) }

    public func chooseModel(_ model: String?) async {
        await services.setModel(model)
    }

    public func signIn() async {
        message = nil
        signingIn = true
        defer { signingIn = false }
        do {
            try await services.signInToChatGPT()
            account = await services.chatGPTAccount()
            models = await services.models()
        } catch ChatGPTAuthError.denied {
            message = "Sign-in was cancelled. Try again when you're ready."
        } catch {
            message = "Couldn't sign in to ChatGPT. Try again."
        }
    }

    public func signOut() async {
        message = nil
        do {
            try await services.signOutOfChatGPT()
            account = nil
            models = []
        } catch {
            message = "Couldn't sign out: \(error.localizedDescription)"
        }
    }

    // MARK: General

    public func setOpenAtLogin(_ on: Bool) {
        do {
            try services.setOpenAtLogin(on)
        } catch {
            message = "macOS didn't let Splark change this. Check System Settings → General → Login Items."
        }
    }

    public func setShowCount(_ on: Bool) async { await services.setShowCount(on) }

    public func setSummariesPaused(_ paused: Bool) async { await services.setSummariesPaused(paused) }

    public func askToReset() { confirmingReset = true }
    public func cancelReset() { confirmingReset = false }

    /// Splark starts over even if a Keychain item wouldn't go: the engine has forgotten everything else, and a leftover
    /// token is replaced when that workspace connects again.
    public func confirmReset() async {
        confirmingReset = false
        try? await services.reset()
        onReset()
    }

    /// Previews and renders only: put the model in a state without going through the services.
    func preview(section: Section, message: String? = nil, working: String? = nil, pasting: String? = nil, removal: WorkspaceRow? = nil,
                 account: ChatGPTAccount? = nil, models: [String] = [], confirmingReset: Bool = false) {
        self.section = section
        self.message = message
        self.working = working
        self.pasting = pasting
        self.removal = removal
        self.account = account
        self.models = models
        self.confirmingReset = confirmingReset
    }

    // MARK: About

    public var version: String { "Version \(SplarkInfo.version) · Open source, MIT licence" }
    public func openRepository() { services.open(URL(string: "https://github.com/ivliag/splark")!) }
    public func openDoll() { services.open(URL(string: "https://github.com/xiaogdgenuine/Doll")!) }
}
