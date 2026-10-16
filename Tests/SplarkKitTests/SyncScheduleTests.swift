import Foundation
import Testing
@testable import SplarkKit

@Suite struct SlackTSTests {
    @Test func comparesAsNumbersNotStrings() {
        #expect(SlackTS.isAfter("1800000000.000010", "1800000000.000009"))
        #expect(SlackTS.isAfter("1800000001.000000", "999999999.999999"))
        #expect(!SlackTS.isAfter("1800000000.000100", "1800000000.000100"))
        #expect(SlackTS.latest("1.000002", nil, "1.000010") == "1.000010")
    }

    @Test func convertsToAndFromDates() {
        #expect(SlackTS.ts(Date(timeIntervalSince1970: 1_800_000_000.5)) == "1800000000.500000")
        #expect(SlackTS.date("1800000000.250000") == Date(timeIntervalSince1970: 1_800_000_000.25))
        #expect(SlackTS.justBefore("1800000000.000000") == "1799999999.999999")
        #expect(SlackTS.justBefore("1800000000.000100") == "1800000000.000099")
    }

    @Test func zeroMeansNeverRead() {
        #expect(SlackTS.isZero("0000000000.000000") && SlackTS.isZero(nil) && !SlackTS.isZero("1.000001"))
    }
}

@Suite struct ConversationTitleTests {
    @Test func titlesByKind() {
        let names = ["U2": "Marta Ruiz"]
        func conversation(_ json: String) -> SlackConversation { try! SlackClient.decoder.decode(SlackConversation.self, from: Data(json.utf8)) }
        #expect(ConversationTitle.make(conversation(#"{"id":"D1","is_im":true,"user":"U2"}"#), names: names, myHandle: "ivan") == "Marta Ruiz")
        #expect(ConversationTitle.make(conversation(#"{"id":"D2","is_im":true,"user":"U3"}"#), names: names, myHandle: "ivan") == "U3")
        #expect(ConversationTitle.make(conversation(#"{"id":"G1","is_mpim":true,"name":"mpdm-marta--ivan--leo.b-1"}"#), names: names, myHandle: "ivan") == "marta, leo.b")
        #expect(ConversationTitle.make(conversation(#"{"id":"C1","is_channel":true,"name":"eng"}"#), names: names, myHandle: "ivan") == "#eng")
    }
}

@Suite struct SyncScheduleTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func schedule() -> SyncSchedule {
        var s = SyncSchedule()
        s.setInventory(["C1": .publicChannel, "D1": .im, "G1": .privateChannel, "M1": .mpim], now: t0)
        return s
    }

    @Test func aColdStartChecksDirectMessagesFirst() {
        var s = schedule()
        var order: [String] = []
        while let id = s.next(now: t0) {
            order.append(id)
            s.checked(id, now: t0, lastActivity: nil, hasUnread: false)
        }
        #expect(order == ["D1", "M1", "G1", "C1"])
        #expect(s.progress == SyncSchedule.Progress(checked: 4, total: 4))
    }

    @Test(arguments: [
        ("D1", nil as TimeInterval?, false, 60.0),        // DMs: 60 s
        ("M1", nil, false, 60),                           // group DMs: 60 s
        ("G1", nil, false, 180),                          // private channels: 3 min
        ("C1", nil, false, 300),                          // public channels: 5 min
        ("C1", -600, false, 60),                          // hot: activity in the last 30 min
        ("C1", -3 * 86400, true, 60),                     // hot: unread now
        ("D1", -15 * 86400, false, 900),                  // dormant: nothing for 14 days
    ])
    func intervalsFollowTheSpec(id: String, activityAgo: TimeInterval?, unread: Bool, interval: TimeInterval) {
        var s = schedule()
        s.checked(id, now: t0, lastActivity: activityAgo.map { t0.addingTimeInterval($0) }, hasUnread: unread)
        #expect(s.entries[id]?.due == t0.addingTimeInterval(interval))
    }

    @Test func aBadgeChangeJumpsDirectAndHotConversationsAheadOfOverdueChannels() {
        var s = schedule()
        for id in ["D1", "M1", "G1", "C1"] { s.checked(id, now: t0, lastActivity: nil, hasUnread: false) }
        s.checked("G1", now: t0, lastActivity: t0, hasUnread: true)       // hot
        let later = t0.addingTimeInterval(400)                            // C1 is overdue now
        s.wakeDirect(now: t0.addingTimeInterval(10))
        var order: [String] = []
        while let id = s.next(now: later), order.count < 4 {
            order.append(id)
            s.checked(id, now: later, lastActivity: nil, hasUnread: false)
        }
        #expect(Array(order.prefix(3)).sorted() == ["D1", "G1", "M1"])
        #expect(order.last == "C1")
    }

    @Test func overdueWorkIsServedOldestFirstSoChannelsAreNotStarved() {
        var s = schedule()
        s.checked("C1", now: t0, lastActivity: nil, hasUnread: false)                           // due t0+300
        s.checked("D1", now: t0.addingTimeInterval(250), lastActivity: nil, hasUnread: false)   // due t0+310
        s.checked("M1", now: t0.addingTimeInterval(260), lastActivity: nil, hasUnread: false)   // due t0+320
        s.checked("G1", now: t0.addingTimeInterval(200), lastActivity: nil, hasUnread: false)   // due t0+380
        #expect(s.next(now: t0.addingTimeInterval(400)) == "C1")   // the public channel has waited longest
    }

    @Test func inventoryChangesKeepExistingTimes() {
        var s = schedule()
        s.checked("C1", now: t0, lastActivity: nil, hasUnread: false)
        s.setInventory(["C1": .publicChannel, "C9": .publicChannel], now: t0.addingTimeInterval(5))
        #expect(s.entries.keys.sorted() == ["C1", "C9"])
        #expect(s.entries["C1"]?.due == t0.addingTimeInterval(300))
        #expect(s.entries["C9"]?.due == t0.addingTimeInterval(5))
        #expect(s.progress == SyncSchedule.Progress(checked: 1, total: 2))
    }

    @Test func postponeAndNextDue() {
        var s = schedule()
        for id in ["D1", "M1", "G1", "C1"] { s.checked(id, now: t0, lastActivity: nil, hasUnread: false) }
        #expect(s.nextDue == t0.addingTimeInterval(60))
        s.postpone("D1", until: t0.addingTimeInterval(1000))
        s.postpone("M1", until: t0.addingTimeInterval(1000))
        #expect(s.nextDue == t0.addingTimeInterval(180))
    }
}
