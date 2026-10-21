import AppKit
import Foundation
import Observation
import os

/// What `SplarkEngine` runs on. `live()` is the real thing; tests swap Slack, the AI, the clock and storage.
public struct EngineEnvironment: Sendable {
    public var secrets: SecretStore
    public var state: StateStore
    public var slack: @Sendable (SlackCredentials) -> SlackAPI
    public var chatGPT: ChatGPTSession
    public var llm: LLMClient?            // nil: the user's ChatGPT plan, through `chatGPT`
    public var badges: BadgeWatcher?      // nil: schedule-only polling
    public var sync: SyncEngine.Config
    public var triage: Triage.Config
    public var now: @Sendable () -> Date
    public var open: @MainActor @Sendable (URL) -> Bool

    public init(secrets: SecretStore, state: StateStore, slack: @escaping @Sendable (SlackCredentials) -> SlackAPI, chatGPT: ChatGPTSession,
                llm: LLMClient?, badges: BadgeWatcher?, sync: SyncEngine.Config, triage: Triage.Config,
                now: @escaping @Sendable () -> Date, open: @escaping @MainActor @Sendable (URL) -> Bool) {
        self.secrets = secrets
        self.state = state
        self.slack = slack
        self.chatGPT = chatGPT
        self.llm = llm
        self.badges = badges
        self.sync = sync
        self.triage = triage
        self.now = now
        self.open = open
    }

    /// The Keychain under `keychainService`, state.json at `stateURL`, real Slack and ChatGPT, and Slack's Dock badge.
    public static func live(keychainService: String = "dev.splark.Splark", stateURL: URL = StateStore.defaultURL) -> EngineEnvironment {
        let secrets = KeychainStore(service: keychainService)
        return EngineEnvironment(
            secrets: secrets, state: StateStore(url: stateURL),
            slack: { SlackClient(tokens: SlackTokenManager(credentials: $0, store: secrets)) },   // one client, one rate limiter per workspace
            chatGPT: ChatGPTSession(store: secrets), llm: nil, badges: BadgeWatcher(), sync: SyncEngine.Config(), triage: Triage.Config(),
            now: { Date() }, open: { NSWorkspace.shared.open($0) })
    }
}

/// A channel for the exclusions picker (spec §4.5).
public struct ChannelOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String   // "#eng"
    public let isPrivate: Bool

    public init(id: String, title: String, isPrivate: Bool) {
        self.id = id
        self.title = title
        self.isPrivate = isPrivate
    }
}

/// The signed-in ChatGPT account, for setup and Settings.
public struct ChatGPTAccount: Sendable, Equatable {
    public let email: String?
    public let canUsePlan: Bool

    public init(email: String?, canUsePlan: Bool) {
        self.email = email
        self.canUsePlan = canUsePlan
    }
}

/// Sleeps until a time, or until poked, whichever comes first.
@MainActor final class Wakeup {
    private var continuation: CheckedContinuation<Void, Never>?
    private var poked = false
    private var generation = 0

    /// `date == nil` waits for a poke.
    func wait(until date: Date?, now: Date) async {
        if poked { poked = false; return }
        fire()   // one waiter at a time: never drop an earlier one
        generation += 1
        let mine = generation
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            guard let date else { return }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSince(now))))
                if self?.generation == mine { self?.fire() }
            }
        }
    }

    func poke() {
        if continuation != nil { fire() } else { poked = true }
    }

    private func fire() {
        let waiting = continuation
        continuation = nil
        waiting?.resume()
    }
}

/// Hands sync results to the inbox and to triage, in the order they happened.
@MainActor final class Feed {
    let inbox: InboxStore
    let triage: Triage
    let wakeup: Wakeup

    init(inbox: InboxStore, triage: Triage, wakeup: Wakeup) {
        self.inbox = inbox
        self.triage = triage
        self.wakeup = wakeup
    }

    func apply(_ update: SyncUpdate) async {
        guard !update.isEmpty else { return }
        inbox.apply(update)
        await triage.update(update)
        wakeup.poke()
    }
}

/// Runs Splark (spec §5.3): a sync loop per workspace, triage, the inbox, the actions and Slack's badge,
/// and keeps state.json up to date. The app's UI (Plan 3) and `splark-dev inbox` drive it.
@MainActor @Observable
public final class SplarkEngine {
    private struct Running {
        let workspace: Workspace
        let slack: SlackAPI
        let engine: SyncEngine
        let names: UserDirectory
        let wakeup = Wakeup()
        var loop: Task<Void, Never>?
    }

    /// Lets `Actions` find a workspace's connection without holding the engine.
    @MainActor private final class Registry {
        var running: [String: Running] = [:]
    }

    public let inbox = InboxStore()
    public let actions: Actions
    public private(set) var syncStatus: [String: SyncStatus] = [:]
    public private(set) var triageState: TriageState = .idle
    public private(set) var isRunning = false
    public private(set) var badge: SlackBadge?   // nil: Slack isn't running, or its badge can't be read
    public var workspaces: [Workspace] { state.workspaces }
    public var pendingApps: [SlackAppRegistration] { state.pendingApps }
    public var settings: SavedState.Settings { state.settings }

    private let environment: EngineEnvironment
    private let triage: Triage
    private let chatGPTClient: ChatGPTLLMClient?
    private let registry = Registry()
    private let triageWakeup = Wakeup()
    private let feed: Feed
    private var state: SavedState
    private var triageLoop: Task<Void, Never>?
    private var saveLoop: Task<Void, Never>?

    public init(environment: EngineEnvironment) {
        self.environment = environment
        let state = environment.state.load()
        self.state = state
        chatGPTClient = environment.llm == nil ? ChatGPTLLMClient(session: environment.chatGPT, chosenModel: state.settings.model, now: environment.now) : nil
        let triage = Triage(llm: environment.llm ?? chatGPTClient, config: environment.triage, now: environment.now)
        self.triage = triage
        let feed = Feed(inbox: inbox, triage: triage, wakeup: triageWakeup)
        self.feed = feed
        let registry = self.registry
        actions = Actions(inbox: inbox, targets: { team in registry.running[team].map { ActionTarget(slack: $0.slack, engine: $0.engine) } },
                          onUpdate: { await feed.apply($0) }, open: environment.open)
    }

    // MARK: Running

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        inbox.setWorkspaces(state.workspaces)
        for (team, channels) in state.excludedChannels { inbox.setExcluded(Set(channels), teamId: team) }
        for workspace in state.workspaces { launch(workspace) }
        triageLoop = Task { [weak self] in await self?.runTriage() }
        saveLoop = Task { [weak self] in
            // A cancelled sleep throws: stop here, rather than save once more after stop() (or reset()) is done.
            while (try? await Task.sleep(for: .seconds(60))) != nil {
                await self?.save()
            }
        }
        environment.badges?.start { [weak self] badge in
            Task { @MainActor in await self?.badgeChanged(badge) }
        }
        let paused = state.settings.summariesPaused
        Task {
            await triage.setPaused(paused)
            await updateReaders()
        }
    }

    /// Sends pending mark-reads, stops every loop and saves state.json.
    public func stop() async {
        guard isRunning else { return }
        environment.badges?.stop()
        await actions.commitPendingReads()
        for running in registry.running.values {
            running.loop?.cancel()
            running.wakeup.poke()
        }
        triageLoop?.cancel()
        triageWakeup.poke()
        saveLoop?.cancel()
        await save()
        registry.running.removeAll()
        isRunning = false
    }

    /// The menu's "Refresh now".
    public func refreshNow() async {
        for running in registry.running.values {
            await running.engine.refreshNow()
            running.wakeup.poke()
        }
        triageWakeup.poke()
    }

    /// From the badge watcher (public for tests).
    public func badgeChanged(_ badge: SlackBadge?) async {
        self.badge = badge
        for running in registry.running.values {
            await apply(await running.engine.badgeChanged(badge))
            running.wakeup.poke()
        }
    }

    // MARK: Workspaces

    /// After setup or a reconnect: keeps the token, records the workspace and (re)starts its sync.
    public func connect(_ connection: SlackConnection) async throws {
        let workspace = connection.workspace
        try connection.credentials.save(to: environment.secrets)
        if let index = state.workspaces.firstIndex(where: { $0.teamId == workspace.teamId }) {
            state.workspaces[index] = workspace
        } else {
            state.workspaces.append(workspace)
        }
        state.pendingApps.removeAll { $0.appId != nil && $0.appId == workspace.appId }
        inbox.setWorkspaces(state.workspaces)
        if isRunning {
            await halt(workspace.teamId)
            launch(workspace)
            await updateReaders()
        }
        await save()
    }

    /// Created but not yet allowed ("Waiting for approval"): kept so "Finish connecting" needs no new config token.
    public func addPendingApp(_ app: SlackAppRegistration) async {
        state.pendingApps.append(app)
        await save()
    }

    public func removePendingApp(_ app: SlackAppRegistration) async {
        state.pendingApps.removeAll { $0 == app }
        await save()
    }

    /// What "Reconnect" re-authorises: the workspace's private app. Nil for a pasted token, which has no app.
    public func registration(for teamId: String) -> SlackAppRegistration? {
        guard let workspace = state.workspaces.first(where: { $0.teamId == teamId }), let port = workspace.redirectPort,
              let clientId = (try? SlackCredentials.load(teamId: teamId, from: environment.secrets)).flatMap({ $0 })?.clientId else { return nil }
        return SlackAppRegistration(appId: workspace.appId, clientId: clientId, redirectPort: port)
    }

    /// Every channel the user is in (excluded ones too), sorted by name. Empty until the first inventory.
    public func channels(teamId: String) async -> [ChannelOption] {
        guard let running = registry.running[teamId] else { return [] }
        return await running.engine.conversations
            .filter { $0.kind == .publicChannel || $0.kind == .privateChannel }
            .map { ChannelOption(id: $0.id, title: "#" + ($0.name ?? $0.id), isPrivate: $0.kind == .privateChannel) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func excludedChannels(teamId: String) -> Set<String> { Set(state.excludedChannels[teamId] ?? []) }

    /// Settings → Remove: forgets the token and everything Splark kept about the workspace.
    /// The workspace goes even when its Keychain item won't; the error then says so.
    public func disconnect(teamId: String) async throws {
        await halt(teamId)
        state.workspaces.removeAll { $0.teamId == teamId }
        state.sync[teamId] = nil
        state.userNames[teamId] = nil
        state.excludedChannels[teamId] = nil
        inbox.setExcluded([], teamId: teamId)
        syncStatus[teamId] = nil
        inbox.setWorkspaces(state.workspaces)
        await save()
        try environment.secrets.delete(SlackCredentials.key(teamId: teamId))
    }

    /// "Mute #eng" in the panel: one more excluded channel. Slack doesn't tell apps which channels are muted there.
    public func mute(channel: String, teamId: String) async {
        await setExcluded(excludedChannels(teamId: teamId).union([channel]), teamId: teamId)
    }

    public func unmute(channel: String, teamId: String) async {
        await setExcluded(excludedChannels(teamId: teamId).subtracting([channel]), teamId: teamId)
    }

    public func setExcluded(_ channels: Set<String>, teamId: String) async {
        state.excludedChannels[teamId] = channels.sorted()
        inbox.setExcluded(channels, teamId: teamId)
        if let running = registry.running[teamId] { await apply(await running.engine.setExcluded(channels)) }
        await save()
    }

    // MARK: Summaries

    public func setSummariesPaused(_ paused: Bool) async {
        state.settings.summariesPaused = paused
        await triage.setPaused(paused)
        triageState = await triage.state
        triageWakeup.poke()
        await save()
    }

    public func setModel(_ model: String?) async {
        state.settings.model = model
        await chatGPTClient?.setModel(model)
        await save()
    }

    /// Settings that only the UI reads: open at login, show count.
    public func updateSettings(_ change: (inout SavedState.Settings) -> Void) async {
        change(&state.settings)
        await save()
    }

    public func signInToChatGPT(open: @Sendable (URL) -> Void) async throws -> ChatGPTCredentials {
        let credentials = try await environment.chatGPT.signIn(open: open)
        await triage.resume()
        triageWakeup.poke()
        return credentials
    }

    public func signOutOfChatGPT() async throws {
        try await environment.chatGPT.signOut()
        await chatGPTClient?.forgetModels()
        await triage.signedOut()
        triageState = await triage.state
    }

    public func chatGPTAccount() async -> ChatGPTAccount? {
        await environment.chatGPT.credentials.map { ChatGPTAccount(email: $0.email, canUsePlan: $0.canUsePlan) }
    }

    /// The plan's models, for Settings' model picker. Empty when summaries come from another LLM client.
    public func availableModels() async throws -> [String] {
        try await chatGPTClient?.models() ?? []
    }

    /// Settings → Reset Splark: stops, then forgets every token, setting and summary. The app shows setup again.
    /// Everything in memory is forgotten even if a Keychain item or the file won't go; the first such error is thrown after.
    public func reset() async throws {
        await stop()
        var failure: Error?
        func attempt(_ body: () throws -> Void) {
            do { try body() } catch { failure = failure ?? error }
        }
        for workspace in state.workspaces { attempt { try environment.secrets.delete(SlackCredentials.key(teamId: workspace.teamId)) } }
        do { try await environment.chatGPT.signOut() } catch { failure = failure ?? error }
        attempt { try environment.secrets.delete(ChatGPTSession.hostKey) }
        attempt { try environment.state.delete() }
        await triage.forgetAll()
        await chatGPTClient?.setModel(nil)
        await chatGPTClient?.forgetModels()
        state = SavedState()
        syncStatus = [:]
        inbox.clear()
        inbox.setWorkspaces([])
        if let failure { throw failure }
    }

    // MARK: Loops

    private func launch(_ workspace: Workspace) {
        let team = workspace.teamId
        let credentials: SlackCredentials
        do {
            guard let saved = try SlackCredentials.load(teamId: team, from: environment.secrets) else {
                return cannotStart(workspace, reason: "No saved token in the Keychain")
            }
            credentials = saved
        } catch {
            return cannotStart(workspace, reason: "Splark couldn't read its Keychain (\(error))")
        }
        let slack = environment.slack(credentials)
        let names = UserDirectory(now: environment.now, entries: state.userNames[team] ?? [:]) { try await slack.usersInfo($0) }
        let engine = SyncEngine(workspace: workspace, slack: slack, names: names, memory: state.sync[team] ?? SyncMemory(),
                                excluded: Set(state.excludedChannels[team] ?? []), config: environment.sync, now: environment.now)
        registry.running[team] = Running(workspace: workspace, slack: slack, engine: engine, names: names)
        registry.running[team]?.loop = Task { [weak self] in await self?.runSync(team) }
    }

    private func cannotStart(_ workspace: Workspace, reason: String) {
        syncStatus[workspace.teamId] = SyncStatus(problem: .reauthorize, reason: reason)
        Logger.sync.error("\(workspace.name, privacy: .public) can't sync: \(reason, privacy: .public)")
    }

    /// Stops one workspace's loop and drops its items, keeping what it learned.
    private func halt(_ teamId: String) async {
        guard let running = registry.running.removeValue(forKey: teamId) else { return }
        running.loop?.cancel()
        running.wakeup.poke()
        state.sync[teamId] = await running.engine.memory
        state.userNames[teamId] = await running.names.entries
        var gone = SyncUpdate()
        for key in await running.engine.snapshots.keys { gone.remove(key) }
        await apply(gone)
    }

    private func runSync(_ team: String) async {
        while !Task.isCancelled, let running = registry.running[team] {
            let step = await running.engine.step()
            guard !Task.isCancelled else { return }
            await apply(step.update)
            syncStatus[team] = await running.engine.status
            if !step.didWork { await running.wakeup.wait(until: step.nextWake, now: environment.now()) }
        }
    }

    private func runTriage() async {
        while !Task.isCancelled {
            if let due = await triage.nextFlush, due <= environment.now() {
                triageState = .summarising(min(await triage.waitingCount, environment.triage.batchSize))
                let results = await triage.flushIfDue()
                guard !Task.isCancelled else { return }   // stopped (or reset) while the request was out
                if !results.isEmpty { inbox.apply(results) }
            }
            triageState = await triage.state
            let next = await triage.nextFlush
            guard !Task.isCancelled else { return }       // a stopped loop must not take a new loop's wake-up
            await triageWakeup.wait(until: next, now: environment.now())
        }
    }

    private func apply(_ update: SyncUpdate) async { await feed.apply(update) }

    /// Who the summaries are written for: the user's display name in each workspace.
    private func updateReaders() async {
        var readers: [String: TriageReader] = [:]
        for (team, running) in registry.running {
            let me = running.workspace.userId
            let name = await running.names.names(for: [me])[me] ?? running.workspace.userName ?? "you"
            readers[team] = TriageReader(name: name, userId: me, workspace: running.workspace.name)
        }
        await triage.setReaders(readers)
    }

    private func save() async {
        for (team, running) in registry.running {
            state.sync[team] = await running.engine.memory
            state.userNames[team] = await running.names.entries
        }
        try? environment.state.save(state)
    }
}
