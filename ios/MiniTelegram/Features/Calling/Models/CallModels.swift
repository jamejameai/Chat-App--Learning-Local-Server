import Foundation

public enum CallType: String, Codable, Sendable {
    case audio
    case video
}

public enum CallState: String, Codable, Sendable {
    case idle
    case dialing
    case ringing
    case connecting
    case connected
    case reconnecting
    case ended
}

public struct CallItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let conversationId: String
    public let conversationTitle: String
    public let callerUserId: String
    public let callerName: String
    public let callType: CallType
    public var status: String // dialing, active, ended, declined, missed
    public let startedAt: Date
    public var endedAt: Date?
    public var durationSeconds: Int
    public let isOutgoing: Bool
    public var livekitRoomName: String?
    public var token: String?

    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        conversationTitle: String,
        callerUserId: String,
        callerName: String,
        callType: CallType,
        status: String = "dialing",
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        durationSeconds: Int = 0,
        isOutgoing: Bool = false,
        livekitRoomName: String? = nil,
        token: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.conversationTitle = conversationTitle
        self.callerUserId = callerUserId
        self.callerName = callerName
        self.callType = callType
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.isOutgoing = isOutgoing
        self.livekitRoomName = livekitRoomName
        self.token = token
    }
}

public struct CallParticipant: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public var isMuted: Bool
    public var isVideoEnabled: Bool
    public var isSpeaking: Bool

    public init(
        id: String,
        name: String,
        isMuted: Bool = false,
        isVideoEnabled: Bool = false,
        isSpeaking: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isMuted = isMuted
        self.isVideoEnabled = isVideoEnabled
        self.isSpeaking = isSpeaking
    }
}
