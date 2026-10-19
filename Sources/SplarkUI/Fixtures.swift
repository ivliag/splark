import Foundation
import SplarkKit
import SwiftUI

/// The prototype's own conversations (design/prototype/panel.html), built through the real `InboxStore`:
/// for SwiftUI previews, `splark-dev render-ui` and tests.
@MainActor public enum Fixtures {
    /// Thursday 15 October 2026, 14:32 local time: the prototype's clock.
    public static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14, minute: 32))!

    public static let workspaces = [
        Workspace(teamId: "T1", name: "Lumen", userId: "U1", userName: "ivan", url: "https://lumen.slack.com/", redirectPort: 53682, appId: "A1"),
        Workspace(teamId: "T2", name: "Lumen Community", userId: "U9", userName: "ivan", url: "https://lumen-community.slack.com/", redirectPort: 53683, appId: "A2"),
    ]

    private struct Conversation {
        let team: String, channel: String, kind: SnapshotKind, title: String
        let level: TriageLevel, lead: String, rest: String, reason: String
        let messages: [(author: String, text: String, clock: String)]
    }

    private static let conversations: [Conversation] = [
        Conversation(team: "T1", channel: "C1", kind: .channel, title: "#incidents", level: .action, lead: "Approve the rollback?",
                     rest: "Checkout is failing for EU cards since the 14:05 deploy; Marta needs your OK.",
                     reason: "Mentions you directly · production impact · waiting on you",
                     messages: [("Deploy Bot", "Deploy v4.12.0 finished (main → prod)", "14:05"),
                                ("Marta Ruiz", "Stripe is declining EU cards since the deploy, ~30% of checkouts failing", "14:24"),
                                ("Marta Ruiz", "@Ivan can I roll back? need your ok, you own billing", "14:28")]),
        Conversation(team: "T1", channel: "D1", kind: .dm, title: "Daniel Cho", level: .action, lead: "Send the signed SOW to Acme",
                     rest: "before 5pm today; legal approved it.", reason: "Direct request · deadline today",
                     messages: [("Daniel Cho", "legal signed off on the Acme SOW 🎉", "14:01"),
                                ("Daniel Cho", "can you send it to their procurement before 5? they close the PO today", "14:07")]),
        Conversation(team: "T1", channel: "C2", kind: .thread, title: "#marketing", level: .question, lead: "Is the pricing-page copy final?",
                     rest: "Priya wants to hand it to design.", reason: "Question in a thread you started",
                     messages: [("Priya Nair", "is the pricing page copy final or still in review? want to hand it to design", "13:52")]),
        Conversation(team: "T1", channel: "D2", kind: .dm, title: "Leo Park", level: .question, lead: "Move tomorrow's 1:1 to Thursday?",
                     rest: "Same time, Leo asks.", reason: "Direct question · needs a yes or no",
                     messages: [("Leo Park", "hey, could we move tomorrow's 1:1 to Thursday same time?", "13:30")]),
        Conversation(team: "T2", channel: "C9", kind: .channel, title: "#help", level: .question, lead: "Does Zapier support custom fields?",
                     rest: "A community member asks; Ines tagged you.", reason: "You were tagged as the person who knows",
                     messages: [("sam.k", "does the zapier integration support custom fields?", "12:20"),
                                ("Ines", "@Ivan you built that one, right?", "12:31")]),
        Conversation(team: "T1", channel: "C3", kind: .channel, title: "#eng", level: .fyi, lead: "CI is moving to the new runners,",
                     rest: "trying it next sprint.", reason: "An update, nothing asked",
                     messages: [("Tom", "new runners are ~2x faster on the integration suite", "13:02"),
                                ("Ana", "let's try next sprint, I'll write the migration ticket", "13:40")]),
        Conversation(team: "T1", channel: "C4", kind: .channel, title: "#general", level: .fyi, lead: "Offsite on Friday:", rest: "the bus leaves at 9:30.",
                     reason: "An announcement", messages: [("Office", "Offsite Friday! Bus leaves 9:30 sharp from the office 🚌", "11:30")]),
        Conversation(team: "T1", channel: "C5", kind: .channel, title: "#random", level: .fyi, lead: "Coffee machine chatter,", rest: "23 messages.",
                     reason: "Chatter", messages: [("Kai", "the new machine makes oat flat whites now ☕️", "14:12")]),
        Conversation(team: "T2", channel: "C8", kind: .channel, title: "#announcements", level: .fyi, lead: "v2.4 release notes", rest: "shared with the community.",
                     reason: "An announcement", messages: [("Ines", "v2.4 is out: bulk edit, faster sync, new Zapier triggers", "09:40")]),
    ]

    /// An inbox holding the prototype's nine conversations: five that need you, four comments.
    public static func inbox() -> InboxStore {
        let store = InboxStore()
        store.setWorkspaces(workspaces)
        var update = SyncUpdate()
        var results: [TriageResult] = []
        for c in conversations {
            let messages = c.messages.map { m in
                SnapshotMessage(ts: SlackTS.ts(at(m.clock)), authorId: nil, author: m.author, text: m.text, mentionsMe: m.text.contains("@Ivan"))
            }
            let key = ItemKey(teamId: c.team, channelId: c.channel, threadTs: c.kind == .thread ? "1739999999.000100" : nil)
            let snapshot = ConversationSnapshot(key: key, kind: c.kind, title: c.title, unread: messages, context: [], moreUnread: false)
            update.upsert(snapshot)
            results.append(TriageResult(key: key, newestTs: snapshot.newestTs,
                                        items: [TriageItem(level: c.level, lead: c.lead, rest: c.rest, reason: c.reason, anchorTs: snapshot.newestTs, byAI: true)]))
        }
        store.apply(update)
        store.apply(results)
        return store
    }

    public static func emptyInbox() -> InboxStore {
        let store = InboxStore()
        store.setWorkspaces(workspaces)
        return store
    }

    /// "14:28" on the fixture day.
    static func at(_ clock: String) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now)!
    }
}

/// Actions that do nothing: for previews and renders.
@MainActor public final class PreviewActions: PanelActions {
    public init() {}
    public func reply(to item: InboxItem, text: String) async throws {}
    public func react(to item: InboxItem, with reaction: Reaction) async throws {}
    public func markRead(_ items: [InboxItem]) -> Actions.UndoToken { Actions.UndoToken() }
    public func undo(_ token: Actions.UndoToken) {}
    public func open(_ item: InboxItem) async {}
}

/// Every state of the panel worth looking at, as (file name, view), for `splark-dev render-ui` and the PR.
@MainActor public enum PanelGallery {
    public static func states() -> [(name: String, view: AnyView)] {
        let inbox = Fixtures.inbox()
        let items = inbox.items
        func model(expand: InboxItem? = nil, comments: Bool = false, toast: Bool = false) -> PanelModel {
            let m = PanelModel(actions: PreviewActions(), close: {}, openSlack: {}, openSettings: {})
            if let expand { m.toggle(expand) }
            m.commentsOpen = comments
            if toast { m.markRead(items[3]) }
            return m
        }
        let catching = HeaderStatus(text: "Catching up… 120 of 300 conversations", working: true)
        return [
            ("panel", AnyView(PanelView(inbox: inbox, status: nil, model: model(), now: Fixtures.now, layout: .snapshot))),
            ("panel-hover", AnyView(PanelView(inbox: inbox, status: nil, model: model(), now: Fixtures.now, forceHover: items[1].id))),
            ("panel-expanded", AnyView(PanelView(inbox: inbox, status: nil, model: model(expand: items[0]), now: Fixtures.now, layout: .snapshot))),
            ("panel-comments", AnyView(PanelView(inbox: inbox, status: catching, model: model(comments: true), now: Fixtures.now, layout: .snapshot))),
            ("panel-toast", AnyView(PanelView(inbox: inbox, status: nil, model: model(toast: true), now: Fixtures.now, layout: .snapshot))),
            ("panel-empty", AnyView(PanelView(inbox: Fixtures.emptyInbox(), status: nil, model: model(), now: Fixtures.now, layout: .snapshot))),
        ]
    }
}

/// Setup services that do nothing: for previews and renders.
@MainActor final class PreviewSetupServices: SetupServices {
    func createApp(configToken: String) async throws -> SlackAppRegistration { SlackAppRegistration(appId: nil, clientId: "", redirectPort: 0) }
    func authorize(_ app: SlackAppRegistration) async throws -> SlackConnection { throw WorkspaceSetupError.cancelled }
    func connect(userToken: String) async throws -> SlackConnection { throw WorkspaceSetupError.cancelled }
    func added(_ connection: SlackConnection) async throws {}
    func waitingForApproval(_ app: SlackAppRegistration) async {}
    func signInToChatGPT() async throws -> ChatGPTAccount { throw WorkspaceSetupError.cancelled }
    func open(_ url: URL) {}
    func setOpenAtLogin(_ on: Bool) {}
    func setShowCount(_ on: Bool) {}
    func finish() {}
}

/// Every setup step and state worth looking at.
@MainActor public enum SetupGallery {
    public static func states() -> [(name: String, view: AnyView)] {
        func view(_ configure: (SetupModel) -> Void) -> AnyView {
            let model = SetupModel(services: PreviewSetupServices())
            configure(model)
            return AnyView(SetupView(model: model))
        }
        let lumen = [Fixtures.workspaces[0]]
        let rejected = SetupModel.message(for: WorkspaceSetupError.tokenRejected("token_expired"))
        return [
            ("setup-welcome", view { $0.preview(step: .welcome) }),
            ("setup-slack", view { $0.preview(step: .slack) }),
            ("setup-slack-error", view { $0.token = "xoxe.xoxp-1-2026…"; $0.preview(step: .slack, slack: .failed(rejected)) }),
            ("setup-slack-allow", view { $0.preview(step: .slack, slack: .waitingForAllow) }),
            ("setup-slack-connected", view { $0.preview(step: .slack, slack: .connected, connected: lumen) }),
            ("setup-slack-approval", view { $0.preview(step: .slack, slack: .waitingForApproval) }),
            ("setup-slack-manual", view { $0.preview(step: .slack, slack: .manual) }),
            ("setup-chatgpt", view { $0.preview(step: .chatgpt, connected: lumen) }),
            ("setup-chatgpt-done", view { $0.preview(step: .chatgpt, connected: lumen, chatgpt: .signedIn(ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true))) }),
            ("setup-done", view { $0.preview(step: .done, connected: lumen) }),
        ]
    }
}

/// Settings' services for previews and renders: the fixture workspaces, one needing a new token, and an app waiting for approval.
@MainActor final class PreviewSettingsServices: SettingsServices {
    var workspaces: [Workspace] {
        Fixtures.workspaces + [Workspace(teamId: "T3", name: "Acme Partners", userId: "U3", userName: "ivan", url: nil, redirectPort: nil, appId: nil)]
    }
    let pendingApps = [SlackAppRegistration(appId: "A4", clientId: "4.4", redirectPort: 53684)]
    var syncStatus: [String: SyncStatus] {
        ["T1": SyncStatus(lastSuccess: Fixtures.now.addingTimeInterval(-60)),
         "T2": SyncStatus(lastSuccess: Fixtures.now.addingTimeInterval(-240)),
         "T3": SyncStatus(problem: .reauthorize, lastSuccess: Fixtures.now.addingTimeInterval(-3 * 3600))]
    }
    let badge: SlackBadge? = .count(3)
    var settings: SavedState.Settings { SavedState.Settings() }
    func channels(teamId: String) async -> [ChannelOption] { [] }
    func excludedChannels(teamId: String) -> Set<String> { [] }
    func setExcluded(_ channels: Set<String>, teamId: String) async {}
    func reconnect(teamId: String) async throws {}
    func finishConnecting(_ app: SlackAppRegistration) async throws {}
    func connect(userToken: String) async throws -> SlackConnection { throw WorkspaceSetupError.cancelled }
    func added(_ connection: SlackConnection) async throws {}
    func remove(teamId: String) async throws {}
    func removePending(_ app: SlackAppRegistration) async {}
    func addWorkspace() {}
    func chatGPTAccount() async -> ChatGPTAccount? { nil }
    func models() async -> [String] { [] }
    func setModel(_ model: String?) async {}
    func signInToChatGPT() async throws {}
    func signOutOfChatGPT() async throws {}
    func setSummariesPaused(_ paused: Bool) async {}
    func setOpenAtLogin(_ on: Bool) throws {}
    func setShowCount(_ on: Bool) async {}
    func reset() async throws {}
    func open(_ url: URL) {}
}

/// Every Settings section and state worth looking at.
@MainActor public enum SettingsGallery {
    public static func states() -> [(name: String, view: AnyView)] {
        func view(_ configure: (SettingsModel) -> Void) -> AnyView {
            let model = SettingsModel(services: PreviewSettingsServices(), now: { Fixtures.now })
            configure(model)
            return AnyView(SettingsView(model: model))
        }
        let account = ChatGPTAccount(email: "ivan@lumen.dev", canUsePlan: true)
        let models = ["gpt-5.6-luna", "gpt-6-luna", "gpt-6-mini"]
        let channels = [ChannelOption(id: "C1", title: "#announcements", isPrivate: false), ChannelOption(id: "C2", title: "#eng", isPrivate: false),
                        ChannelOption(id: "C3", title: "#incidents", isPrivate: false), ChannelOption(id: "G1", title: "#leads", isPrivate: true),
                        ChannelOption(id: "C4", title: "#random", isPrivate: false), ChannelOption(id: "C5", title: "#social", isPrivate: false)]
        return [
            ("settings-workspaces", view { $0.preview(section: .workspaces) }),
            ("settings-workspaces-allow", view { $0.preview(section: .workspaces, message: SetupModel.message(for: WorkspaceSetupError.timedOut), working: "T1") }),
            ("settings-workspaces-paste", view { $0.preview(section: .workspaces, pasting: "T3"); $0.newToken = "xoxp-2026…" }),
            ("settings-workspaces-remove", view { $0.preview(section: .workspaces, removal: $0.workspaceRows[1]) }),
            ("settings-channels", view {
                $0.preview(section: .workspaces)
                $0.channelPicker = ChannelPicker(teamId: "T1", name: "Lumen", channels: channels, excluded: ["C4", "C5"])
            }),
            ("settings-chatgpt", view { $0.preview(section: .chatgpt, account: account, models: models) }),
            ("settings-chatgpt-signed-out", view { $0.preview(section: .chatgpt) }),
            ("settings-general", view { $0.preview(section: .general) }),
            ("settings-general-reset", view { $0.preview(section: .general, confirmingReset: true) }),
            ("settings-about", view { $0.preview(section: .about) }),
        ]
    }
}
