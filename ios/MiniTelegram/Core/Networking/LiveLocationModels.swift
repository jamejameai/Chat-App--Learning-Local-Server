import Foundation

public struct LiveLocationDTO: Codable, Equatable, Identifiable, Sendable {
    public let user_id: String
    public let share_id: String?
    public let username: String?
    public let display_name: String?
    public let avatar_url: String?
    public let latitude: Double
    public let longitude: Double
    public let heading: Double?
    public let accuracy: Double?
    public let updated_at: String

    public var id: String { user_id }

    public var isFresh: Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let updatedAt = formatter.date(from: updated_at)
            ?? ISO8601DateFormatter().date(from: updated_at)
        return updatedAt.map { Date().timeIntervalSince($0) < 120 } ?? false
    }
}

public struct LiveLocationUpdatePayload: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let heading: Double?
    public let accuracy: Double?
}

public struct LiveLocationStartPayload: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let heading: Double?
    public let accuracy: Double?
    public let viewer_ids: [String]
    public let stop_token: String
}

public struct LiveLocationStopPayload: Codable, Sendable {
    public let stop_token: String
}

public struct LiveLocationStopReceipt: Codable, Sendable {
    public let sharing: Bool
}

public struct LiveLocationStopEvent: Codable, Sendable {
    public let user_id: String
    public let share_id: String?
}

public struct LiveLocationUpdateReceipt: Codable, Sendable {
    public let user_id: String
    public let share_id: String?
    public let latitude: Double
    public let longitude: Double
    public let heading: Double?
    public let accuracy: Double?
    public let updated_at: String
    public let viewer_ids: [String]?
}

public struct LiveLocationShareState: Codable, Sendable {
    public let sharing: Bool
    public let location: LiveLocationUpdateReceipt?
}
