import Foundation
import Testing
@testable import SplarkKit

@Suite struct SlackMethodsTests {
    func client(_ stub: StubTransport) -> SlackClient { SlackClient(token: "x", transport: stub, sleeper: RecordingSleeper()) }

    @Test func historyCanAskForMessagesBeforeAPoint() async throws {
        let stub = StubTransport(json: #"{"ok":true,"messages":[{"ts":"5.0","user":"U2","text":"hi"}],"has_more":false}"#)
        let page = try await client(stub).conversationsHistory("C1", oldest: nil, latest: "9.0", inclusive: false, limit: 3)
        #expect(page.messages.map(\.ts) == ["5.0"])
        #expect(stub.formBody(0) == ["channel": "C1", "latest": "9.0", "inclusive": "false", "limit": "3"])
    }

    @Test func repliesAsksForOneThreadSinceAPoint() async throws {
        let stub = StubTransport(json: #"{"ok":true,"messages":[{"ts":"1.0","user":"U1","thread_ts":"1.0","reply_count":2,"latest_reply":"3.0","reply_users":["U2"]},{"ts":"3.0","user":"U2","thread_ts":"1.0","text":"done?"}],"has_more":false}"#)
        let page = try await client(stub).conversationsReplies("C1", ts: "1.0", oldest: "2.0", limit: 40)
        #expect(page.messages.count == 2)
        #expect(page.messages[0].latestReply == "3.0" && page.messages[0].replyUsers == ["U2"])
        #expect(stub.formBody(0) == ["channel": "C1", "ts": "1.0", "oldest": "2.0", "limit": "40"])
        #expect(stub.requests[0].url?.lastPathComponent == "conversations.replies")
    }

    @Test(arguments: [
        (#"{"id":"U2","name":"marta","real_name":"Marta R","profile":{"display_name":"Marta","real_name":"Marta Ruiz"}}"#, "Marta"),
        (#"{"id":"U2","name":"marta","real_name":"Marta R","profile":{"display_name":"","real_name":"Marta Ruiz"}}"#, "Marta Ruiz"),
        (#"{"id":"U2","name":"marta","profile":{}}"#, "marta"),
        (#"{"id":"U2"}"#, "U2"),
    ])
    func userDisplayNameFallsBackSensibly(user: String, name: String) async throws {
        let stub = StubTransport(json: #"{"ok":true,"user":\#(user)}"#)
        #expect(try await client(stub).usersInfo("U2").displayName == name)
        #expect(stub.formBody(0) == ["user": "U2"])
    }

    @Test func postMessageThreadsOnlyWhenAsked() async throws {
        let stub = StubTransport(json: #"{"ok":true,"channel":"C1","ts":"7.0"}"#, #"{"ok":true,"channel":"D1","ts":"8.0"}"#)
        let posted = try await client(stub).chatPostMessage(channel: "C1", text: "on it", threadTs: "1.0")
        _ = try await client(stub).chatPostMessage(channel: "D1", text: "ok", threadTs: nil)
        #expect(posted == SlackPostedMessage(channel: "C1", ts: "7.0"))
        #expect(stub.formBody(0) == ["channel": "C1", "text": "on it", "thread_ts": "1.0"])
        #expect(stub.formBody(1) == ["channel": "D1", "text": "ok"])
    }

    @Test func reactMarkAndPermalink() async throws {
        let stub = StubTransport(json: #"{"ok":true}"#, #"{"ok":true}"#, #"{"ok":true,"channel":"C1","permalink":"https://lumen.slack.com/archives/C1/p1000"}"#)
        try await client(stub).reactionsAdd(channel: "C1", timestamp: "1.0", name: "eyes")
        try await client(stub).conversationsMark(channel: "C1", ts: "2.0")
        let link = try await client(stub).chatGetPermalink(channel: "C1", messageTs: "1.0")
        #expect(stub.requests.map { $0.url!.lastPathComponent } == ["reactions.add", "conversations.mark", "chat.getPermalink"])
        #expect(stub.formBody(0) == ["channel": "C1", "timestamp": "1.0", "name": "eyes"])
        #expect(stub.formBody(1) == ["channel": "C1", "ts": "2.0"])
        #expect(stub.formBody(2) == ["channel": "C1", "message_ts": "1.0"])
        #expect(link.absoluteString == "https://lumen.slack.com/archives/C1/p1000")
    }

    @Test func messagesCarryFilesAndBotNames() throws {
        let json = #"{"ts":"1.0","bot_id":"B1","subtype":"bot_message","bot_profile":{"name":"Deploybot"},"files":[{"name":"plan.pdf","title":"Q3 plan"}],"text":""}"#
        let message = try SlackClient.decoder.decode(SlackMessage.self, from: Data(json.utf8))
        #expect(message.botProfile?.name == "Deploybot")
        #expect(message.files?.first?.name == "plan.pdf")
    }

    @Test func searchMatchesKnowTheirThread() throws {
        let json = #"{"messages":{"total":2,"matches":[{"channel":{"id":"C1"},"ts":"5.0","permalink":"https://x.slack.com/archives/C1/p5?thread_ts=1.0&cid=C1"},{"channel":{"id":"C1"},"ts":"6.0","permalink":"https://x.slack.com/archives/C1/p6"}]}}"#
        let result = try SlackClient.decoder.decode(SlackSearchResult.self, from: Data(json.utf8))
        #expect(result.messages.matches.map(\.threadTs) == ["1.0", nil])
    }
}
