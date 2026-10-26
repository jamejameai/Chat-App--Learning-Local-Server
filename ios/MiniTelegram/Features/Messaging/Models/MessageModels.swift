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

public struct MessageAttachment: Codable, Hashable, Sendable {
    public let id: String
    public let fileName: String
    public let mimeType: String
    public let byteSize: Int64
    public let keyBase64: String
    public let ivBase64: String
    public let sha256Checksum: String
    public let downloadUrl: String
    public var localDecryptedPath: String?

    public init(
        id: String = UUID().uuidString,
        fileName: String,
        mimeType: String,
        byteSize: Int64,
        keyBase64: String,
        ivBase64: String,
        sha256Checksum: String,
        downloadUrl: String,
        localDecryptedPath: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.keyBase64 = keyBase64
        self.ivBase64 = ivBase64
        self.sha256Checksum = sha256Checksum
        self.downloadUrl = downloadUrl
        self.localDecryptedPath = localDecryptedPath
    }
}

public struct VoiceNoteMetadata: Codable, Hashable, Sendable {
    public let durationSeconds: Double
    public let waveformSamples: [Float]

    public init(durationSeconds: Double, waveformSamples: [Float]) {
        self.durationSeconds = durationSeconds
        self.waveformSamples = waveformSamples
    }
}

public struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let conversationId: String
    public let senderUserId: String
    public let senderDeviceId: String
    public let senderName: String
    public var senderRole: String?
    public var senderNameColor: String?
    public var sequenceId: Int64
    public var text: String
    public let replyToMessageId: String?
    public var replyPreview: String?
    public var status: MessageDeliveryStatus
    public let timestamp: Date
    public var reactions: [ReactionItem]
    public var isOutgoing: Bool
    public var attachment: MessageAttachment?
    public var voiceNote: VoiceNoteMetadata?

    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        senderUserId: String,
        senderDeviceId: String = "",
        senderName: String,
        senderRole: String? = nil,
        senderNameColor: String? = nil,
        sequenceId: Int64 = 0,
        text: String,
        replyToMessageId: String? = nil,
        replyPreview: String? = nil,
        status: MessageDeliveryStatus = .sending,
        timestamp: Date = Date(),
        reactions: [ReactionItem] = [],
        isOutgoing: Bool = false,
        attachment: MessageAttachment? = nil,
        voiceNote: VoiceNoteMetadata? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderUserId = senderUserId
        self.senderDeviceId = senderDeviceId
        self.senderName = senderName
        self.senderRole = senderRole
        self.senderNameColor = senderNameColor
        self.sequenceId = sequenceId
        self.text = text
        self.replyToMessageId = replyToMessageId
        self.replyPreview = replyPreview
        self.status = status
        self.timestamp = timestamp
        self.reactions = reactions
        self.isOutgoing = isOutgoing
        self.attachment = attachment
        self.voiceNote = voiceNote
    }
}

public struct ConversationItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let type: String // "direct" | "group" | "channel"
    public var title: String
    public var avatarUrl: String?
    public var lastMessageText: String?
    public var lastMessageTimestamp: Date?
    public var unreadCount: Int
    public var lastSequenceId: Int64
    public var isPinned: Bool
    public var isOnline: Bool
    public var lastSeen: Date?
    public var recipientUserId: String?
    public var recipientRole: String?
    public var recipientBorderTemplate: String?
    public var recipientNameColor: String?
    public var memberCount: Int

    public var isRecipientDeveloper: Bool {
        recipientRole == "owner" || (recipientUserId != nil && recipientUserId == "jame.kh") || title.lowercased().contains("jame")
    }

    public var isRecipientOwner: Bool {
        recipientRole == "owner" || (recipientUserId != nil && recipientUserId == "jame.kh") || title.lowercased().contains("jame")
    }

    public var borderTemplateEnum: ProfileBorderTemplate {
        ProfileBorderTemplate.from(raw: recipientBorderTemplate)
    }

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
        lastSeen: Date? = nil,
        recipientUserId: String? = nil,
        recipientRole: String? = nil,
        recipientBorderTemplate: String? = nil,
        recipientNameColor: String? = nil,
        memberCount: Int = 1
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
        self.lastSeen = lastSeen
        self.recipientUserId = recipientUserId
        self.recipientRole = recipientRole
        self.recipientBorderTemplate = recipientBorderTemplate
        self.recipientNameColor = recipientNameColor
        self.memberCount = memberCount
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

public struct GroupMember: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String?
    public let avatarUrl: String?
    public var role: String // "owner" | "admin" | "member" | "read_only"
    public let joinedAt: String?

    public var title: String {
        displayName?.isEmpty == false ? displayName! : username
    }

    public var isOwner: Bool { role == "owner" }
    public var isAdmin: Bool { role == "admin" || role == "owner" }
}
