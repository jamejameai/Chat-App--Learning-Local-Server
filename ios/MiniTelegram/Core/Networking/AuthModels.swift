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

public struct AuthTokensPayload: Codable, Sendable {
    public let access_token: String
    public let refresh_token: String
}

public struct UserDTO: Codable, Sendable {
    public let id: String
    public let username: String
    public let display_name: String
    public let role: String
    public let avatar_url: String?
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
