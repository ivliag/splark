import Foundation
import Testing
@testable import SplarkKit

@Suite struct ThreadTrackerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aNewWatchIsDueNowAndNeverMovesBack() {
        var tracker = ThreadTracker()
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "5.0", activity: t0, now: t0)
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "3.0", activity: t0, now: t0)
        #expect(tracker.watches.count == 1)
        #expect(tracker.watches.values.first?.seenThrough == "5.0")
        #expect(tracker.due(now: t0).map(\.threadTs) == ["1.0"])
    }

    @Test func seeingAThreadAgainDoesNotMakeItBusy() {
        var tracker = ThreadTracker()
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "1.0", activity: t0.addingTimeInterval(-7200), now: t0)
        tracker.checked(channelId: "C1", threadTs: "1.0", newestReply: nil, now: t0)
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "1.0", activity: t0.addingTimeInterval(-3600), now: t0)
        #expect(tracker.watch(channelId: "C1", threadTs: "1.0")?.lastActivity == t0.addingTimeInterval(-3600))
        #expect(tracker.watch(channelId: "C1", threadTs: "1.0")?.due == t0.addingTimeInterval(180))
    }

    @Test func knowsWhichRepliesItHasNotSeen() {
        var tracker = ThreadTracker()
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "2.0", activity: t0, now: t0)
        #expect(tracker.isUnseen("3.0", channelId: "C1", threadTs: "1.0"))
        tracker.checked(channelId: "C1", threadTs: "1.0", newestReply: "3.0", now: t0)
        #expect(!tracker.isUnseen("3.0", channelId: "C1", threadTs: "1.0"))
        #expect(tracker.isUnseen("4.0", channelId: "C1", threadTs: "1.0"))
        #expect(!tracker.isUnseen("4.0", channelId: "C9", threadTs: "1.0"))
    }

    @Test func replyingOrClearingMovesTheLineForward() {
        var tracker = ThreadTracker()
        tracker.userReplied(channelId: "C1", threadTs: "1.0", ts: "4.0", now: t0)       // starts a watch
        #expect(tracker.watch(channelId: "C1", threadTs: "1.0")?.seenThrough == "4.0")
        tracker.clear(channelId: "C1", threadTs: "1.0", through: "9.0")
        tracker.userReplied(channelId: "C1", threadTs: "1.0", ts: "6.0", now: t0)
        #expect(tracker.watch(channelId: "C1", threadTs: "1.0")?.seenThrough == "9.0")
    }

    @Test func clearAllMovesEveryLine() {
        var tracker = ThreadTracker()
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "2.0", activity: t0, now: t0)
        tracker.watch(channelId: "C2", threadTs: "5.0", seenThrough: "8.0", activity: t0, now: t0)
        tracker.clearAll(through: "7.0")
        #expect(tracker.watch(channelId: "C1", threadTs: "1.0")?.seenThrough == "7.0")
        #expect(tracker.watch(channelId: "C2", threadTs: "5.0")?.seenThrough == "8.0")
    }

    @Test func busyThreadsAreCheckedEveryMinuteQuietOnesEveryThree() {
        var tracker = ThreadTracker()
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "1.0", activity: t0.addingTimeInterval(-7200), now: t0)
        tracker.watch(channelId: "C2", threadTs: "2.0", seenThrough: "2.0", activity: t0.addingTimeInterval(-7200), now: t0)
        tracker.checked(channelId: "C1", threadTs: "1.0", newestReply: SlackTS.ts(t0.addingTimeInterval(-600)), now: t0)
        tracker.checked(channelId: "C2", threadTs: "2.0", newestReply: nil, now: t0)
        #expect(tracker.watch(channelId: "C1", threadTs: "1.0")?.due == t0.addingTimeInterval(60))
        #expect(tracker.watch(channelId: "C2", threadTs: "2.0")?.due == t0.addingTimeInterval(180))
        #expect(tracker.nextDue == t0.addingTimeInterval(60))
        tracker.wake(channelId: "C2", threadTs: "2.0")
        #expect(tracker.due(now: t0).map(\.channelId) == ["C2"])
        tracker.wakeAll()
        #expect(tracker.due(now: t0).count == 2)
    }

    @Test func postponeAndRemove() {
        var tracker = ThreadTracker()
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "1.0", activity: t0, now: t0)
        tracker.postpone(channelId: "C1", threadTs: "1.0", until: t0.addingTimeInterval(42))
        #expect(tracker.nextDue == t0.addingTimeInterval(42))
        tracker.remove(channelId: "C1", threadTs: "1.0")
        #expect(tracker.watches.isEmpty)
    }

    @Test func threadsQuietForAWeekAreForgotten() {
        var tracker = ThreadTracker()
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "1.0", activity: t0, now: t0)
        tracker.watch(channelId: "C2", threadTs: "2.0", seenThrough: "2.0", activity: t0.addingTimeInterval(6 * 86400), now: t0)
        tracker.prune(now: t0.addingTimeInterval(7 * 86400 + 1))
        #expect(tracker.watches.values.map(\.channelId) == ["C2"])
    }

    @Test func survivesARoundTripThroughJSON() throws {
        var tracker = ThreadTracker()
        tracker.watch(channelId: "C1", threadTs: "1.0", seenThrough: "1.5", activity: t0, now: t0)
        tracker.checked(channelId: "C1", threadTs: "1.0", newestReply: "1.7", now: t0)
        let decoded = try JSONDecoder().decode(ThreadTracker.self, from: JSONEncoder().encode(tracker))
        #expect(decoded == tracker)
    }
}
