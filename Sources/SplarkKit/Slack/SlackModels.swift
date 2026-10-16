import Foundation

public struct SlackAuthTest: Decodable, Sendable, Equatable {
    public let userId: String
    public let user: String?
    public let teamId: String
    public let team: String?
    public let url: String?
}

public struct SlackConversation: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String?
    public let user: String?          // the other person, for IMs
    public let isIm: Bool?
    public let isMpim: Bool?
    public let isPrivate: Bool?
    public let isChannel: Bool?
    public let isArchived: Bool?
    public let lastRead: String?      // conversations.info only
    public let unreadCountDisplay: Int?  // conversations.info, DMs only

    public enum Kind: String, Sendable { case im, mpim, privateChannel, publicChannel }
    public var kind: Kind {
        if isIm == true { return .im }
        if isMpim == true { return .mpim }
        if isPrivate == true { return .privateChannel }
        return .publicChannel
    }
}

public struct SlackResponseMetadata: Decodable, Sendable, Equatable { public let nextCursor: String? }

public struct SlackConversationList: Decodable, Sendable { public let channels: [SlackConversation]; public let responseMetadata: SlackResponseMetadata? }
public struct SlackConversationInfo: Decodable, Sendable { public let channel: SlackConversation }

public struct SlackMessage: Decodable, Sendable, Equatable {
    public let ts: String
    public let user: String?
    public let botId: String?
    public let username: String?
    public let subtype: String?
    public let text: String?
    public let threadTs: String?
    public let replyCount: Int?
    public let latestReply: String?
    public let replyUsers: [String]?
    public let files: [SlackFile]?
    public let botProfile: SlackBotProfile?
}

public struct SlackFile: Decodable, Sendable, Equatable { public let name: String?; public let title: String? }
public struct SlackBotProfile: Decodable, Sendable, Equatable { public let name: String? }

public struct SlackUser: Decodable, Sendable, Equatable {
    public struct Profile: Decodable, Sendable, Equatable { public let displayName: String?; public let realName: String? }
    public let id: String
    public let name: String?
    public let realName: String?
    public let profile: Profile?

    /// What Slack shows: the display name, else the full name, else the handle.
    public var displayName: String {
        [profile?.displayName, profile?.realName, realName, name].compactMap { $0 }.first { !$0.isEmpty } ?? id
    }
}

public struct SlackPostedMessage: Decodable, Sendable, Equatable {
    public let channel: String
    public let ts: String
    public init(channel: String, ts: String) { self.channel = channel; self.ts = ts }
}

public struct SlackHistory: Decodable, Sendable {
    public let messages: [SlackMessage]
    public let hasMore: Bool?
    public let responseMetadata: SlackResponseMetadata?
}

public struct SlackSearchResult: Decodable, Sendable {
    public struct Matches: Decodable, Sendable { public let total: Int?; public let matches: [Match] }
    public struct Match: Decodable, Sendable, Equatable {
        public struct Channel: Decodable, Sendable, Equatable { public let id: String; public let name: String? }
        public let channel: Channel
        public let ts: String
        public let user: String?
        public let text: String?
        public let permalink: String?

        /// Search results don't say which thread a reply is in; its permalink does (`?thread_ts=…`).
        public var threadTs: String? {
            permalink.flatMap { URLComponents(string: $0)?.queryItems?.first { $0.name == "thread_ts" }?.value }
        }
    }
    public let messages: Matches
}

public struct SlackManifestCreate: Decodable, Sendable {
    public struct Credentials: Decodable, Sendable { public let clientId: String; public let clientSecret: String? }
    public let appId: String
    public let credentials: Credentials
    public let oauthAuthorizeUrl: String?
}

public struct SlackOAuthAccess: Decodable, Sendable {
    public struct AuthedUser: Decodable, Sendable {
        public let id: String
        public let scope: String?
        public let accessToken: String?
        public let tokenType: String?
        public let refreshToken: String?
        public let expiresIn: Int?
    }
    public struct Team: Decodable, Sendable { public let id: String; public let name: String? }
    public let appId: String?
    public let authedUser: AuthedUser
    public let team: Team?
}

/// `oauth.v2.access` with `grant_type=refresh_token`. Slack documents the token at the top level;
/// the `authed_user` shape of the first exchange is accepted too.
public struct SlackTokenRefresh: Decodable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let expiresIn: Int?
    public let tokenType: String?
    public let authedUser: SlackOAuthAccess.AuthedUser?

    public var userAccessToken: String? { authedUser?.accessToken ?? accessToken }
    public var userRefreshToken: String? { authedUser?.refreshToken ?? refreshToken }
    public var userExpiresIn: Int? { authedUser?.expiresIn ?? expiresIn }
}

extension SlackOAuthAccess.AuthedUser: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "AuthedUser(id: \(id), accessToken: \(Redact.token(accessToken)), refreshToken: \(Redact.token(refreshToken)), expiresIn: \(expiresIn.map(String.init) ?? "nil"))"
    }
    public var debugDescription: String { description }
}

extension SlackOAuthAccess: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "SlackOAuthAccess(team: \(team?.id ?? "nil"), authedUser: \(authedUser))" }
    public var debugDescription: String { description }
}

extension SlackTokenRefresh: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "SlackTokenRefresh(accessToken: \(Redact.token(userAccessToken)), refreshToken: \(Redact.token(userRefreshToken)), expiresIn: \(userExpiresIn.map(String.init) ?? "nil"))"
    }
    public var debugDescription: String { description }
}
