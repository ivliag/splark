import Foundation
import Testing
@testable import SplarkKit

/// A Slack message with only the fields a test cares about.
func slackMessage(_ ts: String, user: String? = "U2", text: String? = "", subtype: String? = nil, threadTs: String? = nil,
                  replyCount: Int? = nil, latestReply: String? = nil, replyUsers: [String]? = nil,
                  botId: String? = nil, username: String? = nil, botName: String? = nil, files: [String]? = nil) -> SlackMessage {
    SlackMessage(ts: ts, user: user, botId: botId, username: username, subtype: subtype, text: text, threadTs: threadTs,
                 replyCount: replyCount, latestReply: latestReply, replyUsers: replyUsers,
                 files: files?.map { SlackFile(name: $0, title: nil) }, botProfile: botName.map { SlackBotProfile(name: $0) })
}

@Suite struct MessageNormalizerTests {
    let normalizer = MessageNormalizer(names: ["U1": "Ivan", "U2": "Marta Ruiz"])

    @Test(arguments: [
        ("<@U2> can you look?", "@Marta Ruiz can you look?"),
        ("ping <@U9>", "ping @U9"),
        ("ping <@U9|leo>", "ping @leo"),
        ("see <#C1|eng> and <#C2>", "see #eng and #C2"),
        ("<!here> deploy at 5, <!channel>, <!everyone>", "@here deploy at 5, @channel, @everyone"),
        ("<!subteam^S1|@oncall> paging", "@oncall paging"),
        ("due <!date^1392734382^{date_short}|Feb 18, 2014>", "due Feb 18, 2014"),
        ("read <https://x.dev/a?b=1|the doc>", "read the doc"),
        ("read <https://x.dev/a>", "read https://x.dev/a"),
        ("mail <mailto:a@b.dev|a@b.dev>", "mail a@b.dev"),
        ("ship it :rocket:", "ship it :rocket:"),
        ("a &lt;b&gt; &amp;amp; c", "a <b> &amp; c"),
        ("  two\nlines  ", "two\nlines"),
    ])
    func turnsMarkupIntoPlainText(markup: String, plain: String) {
        #expect(normalizer.plain(markup) == plain)
    }

    @Test func filesBecomeLabels() {
        #expect(normalizer.text(of: slackMessage("1.0", text: "here you go", files: ["plan.pdf"])) == "here you go [file: plan.pdf]")
        #expect(normalizer.text(of: slackMessage("1.0", text: "", files: ["a.png", "b.png"])) == "[file: a.png] [file: b.png]")
    }

    @Test func authorsAreNamesAndBotsAreLabelled() {
        #expect(normalizer.author(of: slackMessage("1.0", user: "U2")) == "Marta Ruiz")
        #expect(normalizer.author(of: slackMessage("1.0", user: "U7")) == "U7")
        #expect(normalizer.author(of: slackMessage("1.0", user: nil, subtype: "bot_message", botId: "B1", botName: "Deploybot")) == "Deploybot")
        #expect(normalizer.author(of: slackMessage("1.0", user: nil, subtype: "bot_message", botId: "B1", username: "CI")) == "CI")
    }

    @Test func findsMentionsAndTheUsersToLookUp() {
        let message = slackMessage("1.0", user: "U2", text: "<@U1> and <@U3|leo>, see <#C1|eng>")
        #expect(MessageNormalizer.mentions("U1", in: message))
        #expect(!MessageNormalizer.mentions("U4", in: message))
        #expect(MessageNormalizer.userIds(in: message) == ["U2", "U1", "U3"])
    }
}

@Suite struct UserDirectoryTests {
    final class Lookups: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []
        func add(_ id: String) { lock.withLock { ids.append(id) } }
        var all: [String] { lock.withLock { ids } }
    }

    func user(_ id: String, _ name: String) -> SlackUser {
        SlackUser(id: id, name: nil, realName: nil, profile: .init(displayName: name, realName: nil))
    }

    @Test func looksUpEachNameOnceADay() async {
        let clock = ManualClock()
        let lookups = Lookups()
        let directory = UserDirectory(now: { clock.now }) { id in lookups.add(id); return user(id, "name-\(id)") }
        #expect(await directory.names(for: ["U2", "U3"]) == ["U2": "name-U2", "U3": "name-U3"])
        _ = await directory.names(for: ["U2"])
        #expect(lookups.all.sorted() == ["U2", "U3"])
        clock.advance(24 * 3600 + 1)
        _ = await directory.names(for: ["U2"])
        #expect(lookups.all.filter { $0 == "U2" }.count == 2)
    }

    @Test func aFailedLookupKeepsTheOldNameOrLeavesItOut() async {
        let clock = ManualClock()
        let directory = UserDirectory(now: { clock.now }, entries: ["U2": .init(name: "Marta", fetchedAt: clock.now)]) { _ in throw URLError(.notConnectedToInternet) }
        clock.advance(25 * 3600)
        #expect(await directory.names(for: ["U2", "U3"]) == ["U2": "Marta"])
    }

    @Test func aSlackHiccupIsTriedAgainNextTime() async {
        let lookups = Lookups()
        let directory = UserDirectory(now: { Date(timeIntervalSince1970: 0) }) { id in lookups.add(id); throw SlackError.http(503) }
        _ = await directory.names(for: ["U9"])
        _ = await directory.names(for: ["U9"])
        #expect(lookups.all == ["U9", "U9"])
    }

    @Test func anUnknownUserIsNotAskedForAgainToday() async {
        let lookups = Lookups()
        let directory = UserDirectory(now: { Date(timeIntervalSince1970: 0) }) { id in lookups.add(id); throw SlackError.api("user_not_found") }
        _ = await directory.names(for: ["U9"])
        _ = await directory.names(for: ["U9"])
        #expect(lookups.all == ["U9"])
    }
}
