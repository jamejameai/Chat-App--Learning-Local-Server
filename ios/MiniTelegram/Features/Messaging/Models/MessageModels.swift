import Foundation

public enum MessageDeliveryStatus: String, Codable, Sendable {
    case sending
    case sent
    case delivered
    case read
    case failed
}

public struct ReactionItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { emoji }
    public let emoji: String
    public var count: Int
    public var userIds: [String]

    public init(emoji: String, count: Int, userIds: [String]) {
        self.emoji = emoji
        self.count = count
        self.userIds = userIds
    }
}

public struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let conversationId: String
    public let senderUserId: String
    public let senderDeviceId: String
    public let senderName: String
    public var sequenceId: Int64
    public var text: String
    public let replyToMessageId: String?
    public var replyPreview: String?
    public var status: MessageDeliveryStatus
    public let timestamp: Date
    public var reactions: [ReactionItem]
    public var isOutgoing: Bool

    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        senderUserId: String,
        senderDeviceId: String = "",
        senderName: String,
        sequenceId: Int64 = 0,
        text: String,
        replyToMessageId: String? = nil,
        replyPreview: String? = nil,
        status: MessageDeliveryStatus = .sending,
        timestamp: Date = Date(),
        reactions: [ReactionItem] = [],
        isOutgoing: Bool = false
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderUserId = senderUserId
        self.senderDeviceId = senderDeviceId
        self.senderName = senderName
        self.sequenceId = sequenceId
        self.text = text
        self.replyToMessageId = replyToMessageId
        self.replyPreview = replyPreview
        self.status = status
        self.timestamp = timestamp
        self.reactions = reactions
        self.isOutgoing = isOutgoing
    }
}

public struct ConversationItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let type: String // "direct" | "group"
    public var title: String
    public var avatarUrl: String?
    public var lastMessageText: String?
    public var lastMessageTimestamp: Date?
    public var unreadCount: Int
    public var lastSequenceId: Int64
    public var isPinned: Bool
    public var isOnline: Bool
    public var recipientUserId: String?

    public init(
        id: String,
        type: String = "direct",
        title: String,
        avatarUrl: String? = nil,
        lastMessageText: String? = nil,
        lastMessageTimestamp: Date? = nil,
        unreadCount: Int = 0,
        lastSequenceId: Int64 = 0,
        isPinned: Bool = false,
        isOnline: Bool = false,
        recipientUserId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.avatarUrl = avatarUrl
        self.lastMessageText = lastMessageText
        self.lastMessageTimestamp = lastMessageTimestamp
        self.unreadCount = unreadCount
        self.lastSequenceId = lastSequenceId
        self.isPinned = isPinned
        self.isOnline = isOnline
        self.recipientUserId = recipientUserId
    }
}

public struct TeamMember: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatarUrl: String?
    public let role: String
    public let status: String

    public var title: String {
        displayName?.isEmpty == false ? displayName! : username
    }
}
