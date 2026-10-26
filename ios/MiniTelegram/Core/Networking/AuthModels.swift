import Foundation

public struct ValidateInviteResponse: Codable, Sendable {
    public let valid: Bool
    public let role: String
    public let expires_at: String
}

public struct OneTimePrekeyPayload: Codable, Sendable {
    public let key_id: Int
    public let public_key: String

    public init(key_id: Int, public_key: String) {
        self.key_id = key_id
        self.public_key = public_key
    }
}

public struct RegisterInviteRequest: Codable, Sendable {
    public let invitation_code: String
    public let username: String
    public let display_name: String
    public let password: String
    public let device_name: String
    public let identity_key_pub: String
    public let signed_prekey_pub: String
    public let signed_prekey_sig: String
    public let signed_prekey_id: Int
    public let one_time_prekeys: [OneTimePrekeyPayload]
}

public struct RegisterRequest: Codable, Sendable {
    public let username: String
    public let display_name: String
    public let password: String
    public let phone_number: String?
    public let avatar_url: String?
    public let device_name: String
    public let identity_key_pub: String
    public let signed_prekey_pub: String
    public let signed_prekey_sig: String
    public let signed_prekey_id: Int
    public let one_time_prekeys: [OneTimePrekeyPayload]
}

public struct LoginRequest: Codable, Sendable {
    public let username: String // Accepts username or phone number
    public let password: String
    public let device_name: String?
}

public struct AuthTokensPayload: Codable, Sendable {
    public let access_token: String
    public let refresh_token: String
}

public struct UserDTO: Codable, Sendable {
    public let id: String
    public let username: String
    public let display_name: String
    public let role: String
    public let phone_number: String?
    public let avatar_url: String?
    public let bio: String?
    public let developer_profile: DeveloperProfile?
    public let cover_url: String?
    public let border_template: String?
    public let name_color: String?
}


public struct DeveloperProject: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var summary: String
    public var technologies: [String]
    public var repositoryURL: String
    public var liveURL: String
    public var isPinned: Bool

    public var technologiesText: String {
        get { technologies.joined(separator: ", ") }
        set {
            technologies = newValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case technologies
        case repositoryURL = "repository_url"
        case liveURL = "live_url"
        case isPinned = "is_pinned"
    }

    public init(
        id: String = UUID().uuidString,
        title: String = "",
        summary: String = "",
        technologies: [String] = [],
        repositoryURL: String = "",
        liveURL: String = "",
        isPinned: Bool = true
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.technologies = technologies
        self.repositoryURL = repositoryURL
        self.liveURL = liveURL
        self.isPinned = isPinned
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        technologies = try values.decodeIfPresent([String].self, forKey: .technologies) ?? []
        repositoryURL = try values.decodeIfPresent(String.self, forKey: .repositoryURL) ?? ""
        liveURL = try values.decodeIfPresent(String.self, forKey: .liveURL) ?? ""
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
    }
}

public struct DeveloperSocialLinks: Codable, Equatable, Sendable {
    public var linkedinURL: String?
    public var instagramURL: String?
    public var xURL: String?

    enum CodingKeys: String, CodingKey {
        case linkedinURL = "linkedin_url"
        case instagramURL = "instagram_url"
        case xURL = "x_url"
    }

    public init(linkedinURL: String? = nil, instagramURL: String? = nil, xURL: String? = nil) {
        self.linkedinURL = linkedinURL
        self.instagramURL = instagramURL
        self.xURL = xURL
    }
}

public struct DeveloperProfile: Codable, Equatable, Sendable {
    public var headline: String?
    public var skills: [String]
    public var projects: [DeveloperProject]
    public var websiteURL: String?
    public var githubURL: String?
    public var socialLinks: DeveloperSocialLinks
    public var currentlyBuilding: String?
    public var workAvailability: String?
    public var location: String?

    enum CodingKeys: String, CodingKey {
        case headline
        case skills
        case projects
        case websiteURL = "website_url"
        case githubURL = "github_url"
        case socialLinks = "social_links"
        case currentlyBuilding = "currently_building"
        case workAvailability = "work_availability"
        case location
    }

    public init(
        headline: String? = nil,
        skills: [String] = [],
        projects: [DeveloperProject] = [],
        websiteURL: String? = nil,
        githubURL: String? = nil,
        socialLinks: DeveloperSocialLinks = DeveloperSocialLinks(),
        currentlyBuilding: String? = nil,
        workAvailability: String? = nil,
        location: String? = nil
    ) {
        self.headline = headline
        self.skills = skills
        self.projects = projects
        self.websiteURL = websiteURL
        self.githubURL = githubURL
        self.socialLinks = socialLinks
        self.currentlyBuilding = currentlyBuilding
        self.workAvailability = workAvailability
        self.location = location
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        headline = try values.decodeIfPresent(String.self, forKey: .headline)
        skills = try values.decodeIfPresent([String].self, forKey: .skills) ?? []
        projects = try values.decodeIfPresent([DeveloperProject].self, forKey: .projects) ?? []
        websiteURL = try values.decodeIfPresent(String.self, forKey: .websiteURL)
        githubURL = try values.decodeIfPresent(String.self, forKey: .githubURL)
        socialLinks = try values.decodeIfPresent(DeveloperSocialLinks.self, forKey: .socialLinks) ?? DeveloperSocialLinks()
        currentlyBuilding = try values.decodeIfPresent(String.self, forKey: .currentlyBuilding)
        workAvailability = try values.decodeIfPresent(String.self, forKey: .workAvailability)
        location = try values.decodeIfPresent(String.self, forKey: .location)
    }
}

public struct DeviceDTO: Codable, Sendable {
    public let id: String
    public let device_name: String?
    public let platform: String?
    public let identity_key_pub: String?
    public let is_revoked: Bool?
    public let last_active_at: String?
}

public struct AuthResponse: Codable, Sendable {
    public let user: UserDTO
    public let device: DeviceDTO
    public let tokens: AuthTokensPayload
}

public struct FriendDTO: Codable, Identifiable, Sendable {
    public let id: String
    public let username: String
    public let display_name: String
    public let phone_number: String?
    public let avatar_url: String?
    public let bio: String?
    public let status: String?
    public let role: String?
    public let cover_url: String?
    public let border_template: String?
    public let name_color: String?
    public let is_friend: Bool?
    public let friends_since: String?
    public let conversation_id: String?
    public let is_online: Bool?
    public let last_seen: String?

    public var isDeveloper: Bool {
        role == "owner" || username.lowercased() == "jame.kh"
    }

    public var isAppOwner: Bool {
        role == "owner" || username.lowercased() == "jame.kh"
    }

    public var borderTemplateEnum: ProfileBorderTemplate {
        ProfileBorderTemplate.from(raw: border_template)
    }
}

/// GET /friends/profile/:userId — phone number and friendship date are only sent to friends.
public struct UserPublicProfileDTO: Codable, Identifiable, Sendable {
    public let id: String
    public let username: String
    public let display_name: String
    public let avatar_url: String?
    public let bio: String?
    public let developer_profile: DeveloperProfile?
    public let status: String?
    public let role: String?
    public let cover_url: String?
    public let border_template: String?
    public let name_color: String?
    public let created_at: String?
    public let phone_number: String?
    public let is_friend: Bool
    public let friends_since: String?
    public let conversation_id: String?
    public let is_online: Bool?
    public let last_seen: String?

    public var isDeveloper: Bool {
        role == "owner" || username.lowercased() == "jame.kh"
    }

    public var isAppOwner: Bool {
        role == "owner" || username.lowercased() == "jame.kh"
    }

    public var borderTemplateEnum: ProfileBorderTemplate {
        ProfileBorderTemplate.from(raw: border_template)
    }
}

public struct AddFriendPayload: Codable, Sendable {
    public let identifier: String
}

public struct AddFriendResponse: Codable, Sendable {
    public let message: String
    public let friend: FriendDTO
}

public struct UpdateProfilePayload: Codable, Sendable {
    public let display_name: String?
    public let username: String?
    public let phone_number: String?
    public let avatar_url: String?
    public let bio: String?
    public let cover_url: String?
    public let border_template: String?
    public let name_color: String?
    public let developer_profile: DeveloperProfile?

    public init(
        display_name: String?,
        username: String?,
        phone_number: String?,
        avatar_url: String?,
        bio: String?,
        cover_url: String? = nil,
        border_template: String? = nil,
        name_color: String? = nil,
        developer_profile: DeveloperProfile? = nil
    ) {
        self.display_name = display_name
        self.username = username
        self.phone_number = phone_number
        self.avatar_url = avatar_url
        self.bio = bio
        self.cover_url = cover_url
        self.border_template = border_template
        self.name_color = name_color
        self.developer_profile = developer_profile
    }
}

public struct InvitationItemDTO: Codable, Identifiable, Sendable {
    public let id: String
    public let code: String
    public let role: String
    public let expires_at: String
    public let revoked: Bool
    public let used_at: String?
    public let created_at: String
    public let created_by_username: String?
    public let used_by_username: String?
}

public struct CreateInvitationPayload: Codable, Sendable {
    public let role: String
    public let expires_in_days: Int
}

// MARK: - Admin DTOs
public struct AdminUserDTO: Codable, Identifiable, Sendable {
    public let id: String
    public let username: String
    public let display_name: String
    public let phone_number: String?
    public let role: String
    public let status: String
    public let border_template: String?
    public let cover_url: String?
    public let name_color: String?
    public let avatar_url: String?
    public let bio: String?
    public let created_at: String
    public let last_seen_at: String?
    public let active_devices: FlexibleInt64?
    public let friends_count: FlexibleInt64?

    public var isOwner: Bool { role == "owner" || username == "jame.kh" }
    public var isSuperAdmin: Bool { role == "superadmin" || isOwner }
    public var isSuspended: Bool { status == "suspended" }
}

public struct UpdateUserStatusPayload: Codable, Sendable {
    public let status: String

    public init(status: String) {
        self.status = status
    }
}

public struct UpdateUserRolePayload: Codable, Sendable {
    public let role: String

    public init(role: String) {
        self.role = role
    }
}

public struct BroadcastPayload: Codable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public struct SystemStatsDTO: Codable, Sendable {
    public let total_users: Int
    public let active_users: Int
    public let total_conversations: Int
    public let total_messages: Int
    public let total_calls: Int
    public let server_time: String
}

