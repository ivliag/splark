import Foundation
import Testing
@testable import SplarkKit

let community = Workspace(teamId: "T2", name: "Lumen Community", userId: "U9", userName: "ivan", url: nil, redirectPort: nil, appId: nil)

func result(_ snapshot: ConversationSnapshot, _ items: [(TriageLevel, String)]) -> TriageResult {
    TriageResult(key: snapshot.key, newestTs: snapshot.newestTs,
                 items: items.map { TriageItem(level: $0.0, lead: $0.1, rest: "", reason: "why", anchorTs: snapshot.newestTs, byAI: true) })
}

@MainActor @Suite struct InboxStoreTests {
    let dm = snapshot("D1", kind: .dm, title: "Marta Ruiz", unread: [(ts(-600), "Marta Ruiz", "can you approve?", false)])
    let mention = snapshot("C1", title: "#eng", unread: [(ts(-60), "Priya", "<@U1> is it final?", true)])
    let chatter = snapshot("C2", title: "#random", unread: [(ts(-30), "Leo", "coffee?", false)])
    let thread = snapshot("C1", kind: .thread, title: "#eng", thread: ts(-5000), unread: [(ts(-20), "Leo", "done?", false)])
    let otherTeam = snapshot("C7", title: "#announcements", unread: [(ts(-10), "Ines", "v2.4 is out", false)], team: "T2")

    func store(_ snapshots: [ConversationSnapshot]) -> InboxStore {
        let store = InboxStore()
        store.setWorkspaces([lumen, community])
        store.apply(update(snapshots))
        return store
    }

    @Test func sortsByLevelThenDirectnessThenNewest() {
        let s = store([dm, mention, chatter, thread, otherTeam])
        s.apply([result(dm, [(.question, "Approve?")]), result(mention, [(.question, "Final?")]), result(chatter, [(.fyi, "Coffee")]),
                 result(thread, [(.action, "Ship it")]), result(otherTeam, [(.fyi, "Release")])])
        #expect(s.items.map(\.lead) == ["Ship it", "Final?", "Approve?", "Release", "Coffee"])
    }

    @Test func showsTheHeuristicUntilSummarisedAndKeepsAnOldSummaryUntilTheNewOne() {
        let s = store([dm, chatter])
        #expect(s.items.map(\.byAI) == [false, false])
        #expect(s.items.map(\.level) == [.question, .fyi])
        s.apply([result(dm, [(.action, "Approve the rollback")])])
        #expect(s.items[0].lead == "Approve the rollback")
        let newer = snapshot("D1", kind: .dm, title: "Marta Ruiz", unread: [(ts(-600), "Marta Ruiz", "can you approve?", false), (ts(-5), "Marta Ruiz", "??", false)])
        s.apply(update([newer]))
        #expect(s.items[0].lead == "Approve the rollback")   // until the new summary arrives
    }

    @Test(arguments: [
        ([] as [TriageLevel], "All caught up", SparkLevel.dimmed, 0),
        ([.fyi, .fyi], "Nothing needs you", .dimmed, 0),
        ([.question, .fyi], "1 needs you", .brighter, 1),
        ([.question, .action, .question], "3 need you", .bright, 3),
    ])
    func summarisesForTheMenuBarAndHeader(levels: [TriageLevel], headline: String, spark: SparkLevel, count: Int) {
        let snapshots = levels.indices.map { snapshot("C\($0)", unread: [(ts(-$0), "Leo", "x", false)]) }
        let s = store(snapshots)
        s.apply(zip(snapshots, levels).map { result($0, [($1, "lead")]) })
        #expect(s.summary == InboxSummary(needYou: count, spark: spark, headline: headline, comments: levels.filter { $0 == .fyi }.count))
    }

    @Test func namesOnlyLaterWorkspaces() {
        let s = store([dm, otherTeam])
        #expect(s.items.first { $0.key.teamId == "T1" }?.workspaceLabel == nil)
        #expect(s.items.first { $0.key.teamId == "T2" }?.workspaceLabel == "Lumen Community")
    }

    @Test func sourcesAndReplyPlaceholders() {
        let s = store([dm, thread, chatter])
        let byChannel = Dictionary(uniqueKeysWithValues: s.items.map { ($0.key, $0) })
        #expect(byChannel[dm.key]?.source == "Marta Ruiz" && byChannel[dm.key]?.replyPlaceholder == "Message Marta Ruiz")
        #expect(byChannel[thread.key]?.source == "thread in #eng" && byChannel[thread.key]?.replyPlaceholder == "Reply in thread")
        #expect(byChannel[chatter.key]?.source == "#random" && byChannel[chatter.key]?.replyPlaceholder == "Reply in thread")
    }

    @Test func excludedChannelsDisappear() {
        let s = store([dm, chatter])
        s.setExcluded(["C2"], teamId: "T1")
        #expect(s.items.map(\.key) == [dm.key])
    }

    @Test func aHiddenConversationReturnsOnlyWithANewerMessage() {
        let s = store([dm, chatter])
        s.hide(dm.key, through: dm.newestTs)
        #expect(s.items.map(\.key) == [chatter.key])
        s.apply(update([dm]))                    // the same messages again: still hidden
        #expect(s.items.map(\.key) == [chatter.key])
        s.unhide(dm.key)
        #expect(s.items.count == 2)
        s.hide(dm.key, through: dm.newestTs)
        s.apply(update([snapshot("D1", kind: .dm, title: "Marta Ruiz", unread: [(ts(-1), "Marta Ruiz", "hello?", false)])]))
        #expect(s.items.count == 2)
    }

    @Test func repliedAndReactionsShowUntilTheConversationMoves() throws {
        let s = store([dm])
        let id = try #require(s.items.first?.id)
        s.markReplied(dm.key)
        s.addReaction(.eyes, to: id)
        s.addReaction(.eyes, to: id)
        s.addReaction(.thumbsUp, to: id)
        #expect(s.items[0].replied && s.items[0].reactions == [.eyes, .thumbsUp])
        s.removeReaction(.eyes, from: id)
        #expect(s.items[0].reactions == [.thumbsUp])
        s.apply(update([snapshot("D1", kind: .dm, title: "Marta Ruiz", unread: [(ts(-600), "Marta Ruiz", "can you approve?", false), (ts(-1), "Marta Ruiz", "and?", false)])]))
        #expect(!s.items[0].replied)
        s.apply(update([], removed: [dm.key]))
        #expect(s.items.isEmpty)
    }

    @Test func showsTheLastTenMessagesAndCountsTheRest() {
        let long = snapshot("C1", unread: (0..<14).map { (ts(-100 + $0), "Leo", "m\($0)", false) })
        let item = store([long]).items[0]
        #expect(item.messages.map(\.text) == (4..<14).map { "m\($0)" })
        #expect(item.earlier == 4)
    }

    @Test func aConversationCanHoldTwoItems() {
        let s = store([mention])
        s.apply([result(mention, [(.action, "Ship it"), (.question, "Final?")])])
        #expect(s.items.map(\.lead) == ["Ship it", "Final?"])
        #expect(Set(s.items.map(\.id)).count == 2)
        #expect(s.summary.needYou == 2)
    }
}
