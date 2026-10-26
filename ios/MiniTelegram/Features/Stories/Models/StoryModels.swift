import Foundation

public struct StoryReactionSummary: Codable, Identifiable, Hashable, Sendable {
    public let reaction: String
    public let count: Int
    public var id: String { reaction }

    public init(reaction: String, count: Int) {
        self.reaction = reaction
        self.count = count
    }
}

/// One photo in someone's story (lives 24 hours).
public struct StoryItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let attachment_id: String
    public let media_key: String
    public let media_iv: String
    public let media_sha256: String
    public let mime_type: String
    public let caption: String?
    public let created_at: String
    public let expires_at: String
    public var viewed: Bool
    /// Only filled in for my own stories
    public let view_count: Int?
    public let reactions_summary: [StoryReactionSummary]?

    /// The encrypted photo, in the shape the attachment downloader understands
    public var attachment: MessageAttachment {
        MessageAttachment(
            id: attachment_id,
            fileName: "story.jpg",
            mimeType: mime_type,
            byteSize: 0,
            keyBase64: media_key,
            ivBase64: media_iv,
            sha256Checksum: media_sha256,
            downloadUrl: "/attachments/\(attachment_id)/download"
        )
    }

    public var createdDate: Date? { StoryDates.parse(created_at) }
}

/// Everything one person has posted, as shown by one circle in the story bar.
public struct UserStories: Codable, Identifiable, Hashable, Sendable {
    public let user_id: String
    public let username: String
    public let display_name: String
    public let avatar_url: String?
    public let role: String?
    public let border_template: String?
    public let name_color: String?
    public let is_me: Bool
    public var has_unseen: Bool
    public var stories: [StoryItem]

    public var isDeveloper: Bool {
        role == "owner" || username.lowercased() == "jame.kh"
    }

    public var isAppOwner: Bool {
        role == "owner" || username.lowercased() == "jame.kh"
    }

    public var borderTemplateEnum: ProfileBorderTemplate {
        ProfileBorderTemplate.from(raw: border_template)
    }

    public var id: String { user_id }

    /// Where to start playing: the first story not seen yet, like Telegram
    public var firstUnseenIndex: Int {
        stories.firstIndex { !$0.viewed } ?? 0
    }
}

/// How the ring around someone's photo is drawn.
public enum StoryRingState: Sendable {
    case none
    case unseen
    case seen
}

enum StoryDates {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }

    /// "Just now", "5m ago", "3h ago"
    static func relative(_ text: String) -> String {
        guard let date = parse(text) else { return "" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
