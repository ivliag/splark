import Foundation
import Testing
@testable import SplarkKit
@testable import SplarkUI

/// Records what the panel asked for; can be told to fail.
@MainActor final class FakeActions: PanelActions {
    var replies: [(String, String)] = []
    var reactions: [Reaction] = []
    var marked: [[String]] = []
    var undone: [Actions.UndoToken] = []
    var opened: [String] = []
    var failReply = false, failReact = false
    var holdReplies = false
    var replyCalls = 0
    private var replyGates: [CheckedContinuation<Void, Never>] = []
    let token = Actions.UndoToken()

    func reply(to item: InboxItem, text: String) async throws {
        replyCalls += 1
        if holdReplies { await withCheckedContinuation { replyGates.append($0) } }
        if failReply { throw ActionError.offline }
        replies.append((item.key.channelId, text))
    }
    func releaseReplies() {
        replyGates.forEach { $0.resume() }
        replyGates = []
    }
    func react(to item: InboxItem, with reaction: Reaction) async throws {
        if failReact { throw ActionError.slack("not_reactable") }
        reactions.append(reaction)
    }
    func markRead(_ items: [InboxItem]) -> Actions.UndoToken {
        marked.append(items.map(\.key.channelId))
        return token
    }
    func undo(_ token: Actions.UndoToken) { undone.append(token) }
    func open(_ item: InboxItem) async { opened.append(item.key.channelId) }
}

@MainActor final class FakeMuting: ChannelMuting {
    var calls: [String] = []
    func mute(channel: String, teamId: String) async { calls.append("mute \(teamId)/\(channel)") }
    func unmute(channel: String, teamId: String) async { calls.append("unmute \(teamId)/\(channel)") }
}

@MainActor @Suite struct PanelModelTests {
    let actions = FakeActions()
    let calls = Calls()

    func model(toast: Duration = .seconds(4)) -> PanelModel {
        let calls = self.calls
        return PanelModel(actions: actions, toastDuration: toast, close: { calls.log.append("close") },
                          openSlack: { calls.log.append("slack") }, openSettings: { calls.log.append("settings") })
    }

    @Test func clickingARowExpandsItAndClickingAgainCollapses() {
        let m = model(), row = item()
        m.toggle(row)
        #expect(m.expanded == row.id)
        m.toggle(row)
        #expect(m.expanded == nil)
    }

    @Test func escapeCollapsesFirstThenCloses() {
        let m = model()
        m.toggle(item())
        m.escape()
        #expect(m.expanded == nil && calls.log.isEmpty)
        m.escape()
        #expect(calls.log == ["close"])
    }

    @Test func sendingAReplyClearsItAndCollapses() async {
        let m = model(), row = item()
        m.startReply(row)
        #expect(m.expanded == row.id && m.focusedReply == row.id)
        m.drafts[row.id] = "  on it  "
        await m.send(row)
        #expect(actions.replies.map(\.1) == ["  on it  "])
        #expect(m.drafts[row.id] == nil && m.expanded == nil)
    }

    @Test func aBlankReplyIsNotSent() async {
        let m = model(), row = item()
        m.drafts[row.id] = "   "
        await m.send(row)
        #expect(actions.replies.isEmpty)
    }

    @Test func aFailedReplyKeepsTheTextAndSaysSo() async {
        actions.failReply = true
        let m = model(), row = item()
        m.toggle(row)
        m.drafts[row.id] = "on it"
        await m.send(row)
        #expect(m.drafts[row.id] == "on it" && m.expanded == row.id)
        #expect(m.toast == PanelModel.Toast(text: "Couldn't send. Try again.", undo: nil))
    }

    @Test func markReadOffersUndoForFourSeconds() async throws {
        let m = model(toast: .milliseconds(80)), row = item()
        m.toggle(row)
        m.markRead(row)
        #expect(actions.marked == [["C1"]] && m.expanded == nil)
        #expect(m.toast == PanelModel.Toast(text: "Marked as read", undo: .markRead(actions.token)))
        #expect(await eventually { m.toast == nil })
    }

    @Test func undoPutsItBack() {
        let m = model(), row = item()
        m.markRead(row)
        m.undo()
        #expect(actions.undone == [actions.token] && m.toast == nil)
    }

    @Test func markAllCommentsRead() {
        let m = model()
        m.commentsOpen = true
        m.markAllRead([item(), item()])
        #expect(actions.marked == [["C1", "C1"]])
        #expect(m.toast?.text == "Marked 2 as read" && !m.commentsOpen)
    }

    @Test func openingInSlackClosesThePanel() async {
        let m = model()
        await m.open(item())
        #expect(actions.opened == ["C1"] && calls.log == ["close"])
    }

    @Test func aFailedReactionSaysSo() async {
        actions.failReact = true
        let m = model()
        await m.react(item(), .eyes)
        #expect(m.toast?.text == "Couldn't add the reaction. Try again.")
    }

    @Test func failuresFromLaterReachTheToast() {
        let m = model()
        m.showFailure(ActionFailure(key: ItemKey(teamId: "T1", channelId: "C1"), message: "Couldn't mark it as read. Try again."))
        #expect(m.toast == PanelModel.Toast(text: "Couldn't mark it as read. Try again.", undo: nil))
    }

    @Test func headerButtons() {
        let m = model()
        m.openSlackApp()
        m.showSettings()
        #expect(calls.log == ["slack", "close", "settings", "close"])
    }

    /// Slack can be slow: a second Enter (or a click on ↑) while the first reply is on its way sends nothing.
    @Test func aSecondSendWhileTheFirstIsOnItsWaySendsNothing() async throws {
        actions.holdReplies = true
        let m = model(), row = item(kind: .dm, title: "Marta Ruiz")
        m.startReply(row)
        m.drafts[row.id] = "on it"
        let first = Task { await m.send(row) }
        #expect(await eventually { actions.replyCalls == 1 })
        #expect(m.sending.contains(row.id))
        let second = Task { await m.send(row) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(actions.replyCalls == 1)
        actions.releaseReplies()
        await first.value
        await second.value
        #expect(actions.replies.map(\.1) == ["on it"] && m.sending.isEmpty)
    }

    @Test func closingThePanelCollapsesTheOpenRow() {
        let m = model(), row = item()
        m.startReply(row)
        m.panelClosed()
        #expect(m.expanded == nil && m.focusedReply == nil)
    }

    /// Two items in one channel reply in two threads: each keeps its own draft, and sending one leaves the other.
    @Test func twoItemsInOneChannelHaveTheirOwnDrafts() async {
        let key = ItemKey(teamId: "T1", channelId: "C1")
        let first = SlackTS.ts(ago(600)), second = SlackTS.ts(ago(60))
        let snapshot = ConversationSnapshot(key: key, kind: .channel, title: "#eng", unread: [
            SnapshotMessage(ts: first, authorId: "U2", author: "Marta Ruiz", text: "can I roll back?", mentionsMe: false),
            SnapshotMessage(ts: second, authorId: "U3", author: "Tom", text: "PR ready for review", mentionsMe: false),
        ], context: [], moreUnread: false)
        let store = InboxStore()
        store.setWorkspaces([lumen])
        var update = SyncUpdate()
        update.upsert(snapshot)
        store.apply(update)
        store.apply([TriageResult(key: key, newestTs: second, items: [
            TriageItem(level: .action, lead: "Approve the rollback?", rest: "", reason: "", anchorTs: first, byAI: true),
            TriageItem(level: .question, lead: "Review the PR?", rest: "", reason: "", anchorTs: second, byAI: true),
        ])])
        let (rollback, review) = (store.items[0], store.items[1])
        let m = model()
        m.drafts[rollback.id] = "Approved, go ahead"
        #expect(m.drafts[review.id] == nil)
        m.drafts[review.id] = "Looking now"
        await m.send(rollback)
        #expect(m.drafts[rollback.id] == nil && m.drafts[review.id] == "Looking now")
    }

    /// Slack doesn't tell apps which channels are muted, so muting is Splark's own: from the open message, with Undo.
    @Test func mutingAChannelFromTheMessageWithUndo() async {
        let muting = FakeMuting()
        let m = PanelModel(actions: actions, muting: muting, close: {}, openSlack: {}, openSettings: {})
        let row = item(title: "#eng")
        #expect(row.canMute)
        m.toggle(row)
        await m.mute(row)
        #expect(muting.calls == ["mute T1/C1"] && m.expanded == nil)
        #expect(m.toast == PanelModel.Toast(text: "Muted #eng", undo: .unmute(row.key)))
        m.undo()
        #expect(await eventually { muting.calls == ["mute T1/C1", "unmute T1/C1"] })
        #expect(m.toast == nil)
    }

    @Test func directMessagesCantBeMuted() async {
        let muting = FakeMuting()
        let m = PanelModel(actions: actions, muting: muting, close: {}, openSlack: {}, openSettings: {})
        let dm = item(kind: .dm, title: "Marta Ruiz")
        #expect(!dm.canMute)
        await m.mute(dm)
        #expect(muting.calls.isEmpty && m.toast == nil)
    }
}
