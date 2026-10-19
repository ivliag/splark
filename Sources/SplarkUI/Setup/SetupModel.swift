import Foundation
import Observation
import SplarkKit

/// What setup needs from outside: Slack's app creation and Allow, the engine, ChatGPT, the browser and settings.
/// `LiveSetupServices` is the real one; tests use a fake.
@MainActor public protocol SetupServices: AnyObject {
    func createApp(configToken: String) async throws -> SlackAppRegistration
    func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection
    func connect(userToken: String) async throws -> SlackConnection
    func added(_ connection: SlackConnection) async throws
    func waitingForApproval(_ app: SlackAppRegistration) async
    func signInToChatGPT() async throws -> ChatGPTAccount
    func open(_ url: URL)
    func setOpenAtLogin(_ on: Bool)
    func setShowCount(_ on: Bool)
    func finish()
}

/// First-run setup (spec §4.4, design/prototype/setup.html): welcome, connect Slack (any number of workspaces),
/// connect ChatGPT, done.
@MainActor @Observable public final class SetupModel {
    public enum Step: Int, CaseIterable { case welcome, slack, chatgpt, done }

    public enum SlackState: Equatable {
        case idle                       // the config-token form
        case creating                   // "Creating your private Slack app…"
        case waitingForAllow            // "Waiting for you to click Allow in your browser…"
        case connected                  // the list, "+ Add another workspace"
        case failed(String)             // the token was refused: fix it and Connect again
        case allowFailed(String)        // the app exists: Try again reopens Allow
        case waitingForApproval         // an admin must approve; Settings finishes later
        case manual                     // "Having trouble?": paste a user token
    }

    public enum ChatGPTState: Equatable {
        case idle, waiting
        case signedIn(ChatGPTAccount)
        case failed(String)
    }

    public var step: Step = .welcome
    public var token = ""         // the pasted app configuration token
    public var manualToken = ""   // the fallback's user token
    public private(set) var slack: SlackState = .idle
    public private(set) var connected: [Workspace] = []
    public private(set) var chatgpt: ChatGPTState = .idle
    public var openAtLogin = true   // applied on Done
    public var showCount = true

    private let services: SetupServices
    private var app: SlackAppRegistration?
    private var attempt = 0   // so an abandoned Allow can't change the state later
    private var allowTask: Task<SlackConnection, Error>?   // holds the app's redirect port while it waits

    public init(services: SetupServices) { self.services = services }

    public var canConnect: Bool {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return slack == .idle || slack == .connected || slack == .waitingForApproval || isFailed
    }

    private var isFailed: Bool { if case .failed = slack { true } else { false } }

    public var canContinue: Bool {
        switch step {
        case .welcome, .done: return true
        case .slack: return !connected.isEmpty || slack == .waitingForApproval
        case .chatgpt:
            switch chatgpt {
            case .signedIn: return true
            case .failed(let message): return message == Self.notEligible
            default: return false
            }
        }
    }

    public func next() { step = Step(rawValue: step.rawValue + 1) ?? .done }
    public func back() { step = Step(rawValue: step.rawValue - 1) ?? .welcome }

    // MARK: Slack

    /// Connect: create the private app with the config token (then forget it), and wait for Allow.
    public func connect() async {
        let configToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !configToken.isEmpty else { return }
        slack = .creating
        do {
            app = try await services.createApp(configToken: configToken)
            token = ""
        } catch {
            slack = .failed(Self.message(for: error))
            return
        }
        await allow()
    }

    /// After a cancelled, timed-out or blocked Allow: the same app, no new token.
    public func retryAllow() async { await allow() }

    private func allow() async {
        guard let app else { return }
        attempt += 1
        let mine = attempt
        slack = .waitingForAllow
        let task = Task { try await services.authorize(app) }
        allowTask = task
        do {
            let connection = try await task.value
            guard mine == attempt else { return }
            try await services.added(connection)
            connected.append(connection.workspace)
            self.app = nil
            slack = .connected
        } catch {
            guard mine == attempt else { return }
            slack = .allowFailed(Self.message(for: error))
        }
    }

    /// Stops waiting for Allow, freeing the redirect port: the window closed, or the user clicked Cancel.
    public func cancel() {
        guard let allowTask else { return }
        allowTask.cancel()
        self.allowTask = nil
        if slack == .waitingForAllow { slack = .allowFailed(Self.message(for: WorkspaceSetupError.cancelled)) }
        attempt += 1
    }

    /// "My workspace needs admin approval": keep the app for Settings' Finish connecting, and carry on.
    public func needsApproval() async {
        guard let app else { return }
        allowTask?.cancel()
        allowTask = nil
        attempt += 1
        await services.waitingForApproval(app)
        self.app = nil
        slack = .waitingForApproval
    }

    public func addAnother() { slack = .idle }

    public func showManual() { slack = .manual }

    public func openSlackAppSettings() { services.open(URL(string: "https://api.slack.com/apps")!) }

    public func openManifestLink() {
        if let url = try? SlackAppManifest.createFromManifestURL() { services.open(url) }
    }

    public func connectManual() async {
        let userToken = manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userToken.isEmpty else { return }
        do {
            let connection = try await services.connect(userToken: userToken)
            try await services.added(connection)
            connected.append(connection.workspace)
            manualToken = ""
            slack = .connected
        } catch {
            slack = .failed(Self.message(for: error))
        }
    }

    // MARK: ChatGPT

    static let notEligible = "This ChatGPT plan can't be used for summaries. Splark will still rank what's unread, without summaries."

    public func signIn() async {
        chatgpt = .waiting
        do {
            let account = try await services.signInToChatGPT()
            chatgpt = account.canUsePlan ? .signedIn(account) : .failed(Self.notEligible)
        } catch ChatGPTAuthError.denied {
            chatgpt = .failed("Sign-in was cancelled. Try again when you're ready.")
        } catch {
            chatgpt = .failed("Couldn't sign in to ChatGPT. Try again.")
        }
    }

    /// Previews and renders only: put the model in a state without going through Slack.
    func preview(step: Step, slack: SlackState = .idle, connected: [Workspace] = [], chatgpt: ChatGPTState = .idle) {
        self.step = step
        self.slack = slack
        self.connected = connected
        self.chatgpt = chatgpt
    }

    // MARK: Done

    public var doneMessage: String {
        let count = connected.count
        let first = count == 0
            ? "Splark is in your menu bar now. It starts catching up once your workspace is approved."
            : "Splark is in your menu bar now and is catching up on \(count) workspace\(count == 1 ? "" : "s")."
        return first + "\nClick the spark to see what needs you."
    }

    public func finish() {
        services.setOpenAtLogin(openAtLogin)
        services.setShowCount(showCount)
        services.finish()
    }

    static func message(for error: Error) -> String {
        switch error {
        case WorkspaceSetupError.tokenRejected:
            return "That token didn't work. Setup tokens expire after 12 hours and are tied to one workspace. Generate a fresh one and paste it again."
        case WorkspaceSetupError.noFreePort:
            return "Splark's sign-in ports (53682–53691) are all in use. Quit the app using them and try again."
        case WorkspaceSetupError.portBusy(let port):
            return "Another app is using port \(port), which your Splark app needs. Quit it and click Try again."
        case WorkspaceSetupError.cancelled:
            return "Slack sign-in was cancelled. Click Try again when you're ready."
        case WorkspaceSetupError.timedOut:
            return "Slack didn't answer in time. Click Try again."
        case is URLError:
            return "Couldn't reach Slack. Check your connection and try again."
        default:
            return "Slack said no (\(error)). Try again, or use a pasted token under Having trouble?"
        }
    }
}
