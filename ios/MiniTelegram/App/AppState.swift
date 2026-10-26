import SwiftUI
import Combine

public enum AppTab: Hashable {
    case chats
    case profile
    case liveLocation
    case settings
}

public struct UserProfile: Codable, Equatable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String
    public let role: String
    public let phoneNumber: String?
    public let avatarUrl: String?
    public let bio: String?
    public let coverUrl: String?
    public let borderTemplate: String?
    public let nameColor: String?
    public let developerProfile: DeveloperProfile?

    public var isAppOwner: Bool {
        role == "owner" || username == "jame.kh"
    }

    public var isSuperAdmin: Bool {
        role == "superadmin" || isAppOwner
    }

    public var isDeveloper: Bool {
        isAppOwner || (developerProfile != nil && !((developerProfile?.skills.isEmpty ?? true) && (developerProfile?.projects.isEmpty ?? true) && (developerProfile?.headline?.isEmpty ?? true)))
    }

    public var borderTemplateEnum: ProfileBorderTemplate {
        ProfileBorderTemplate.from(raw: borderTemplate)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case role
        case phoneNumber = "phone_number"
        case avatarUrl = "avatar_url"
        case bio
        case coverUrl = "cover_url"
        case borderTemplate = "border_template"
        case nameColor = "name_color"
        case developerProfile = "developer_profile"
    }

    public init(
        id: String,
        username: String,
        displayName: String,
        role: String,
        phoneNumber: String? = nil,
        avatarUrl: String? = nil,
        bio: String? = nil,
        coverUrl: String? = nil,
        borderTemplate: String? = nil,
        nameColor: String? = nil,
        developerProfile: DeveloperProfile? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.role = role
        self.phoneNumber = phoneNumber
        self.avatarUrl = avatarUrl
        self.bio = bio
        self.coverUrl = coverUrl
        self.borderTemplate = borderTemplate
        self.nameColor = nameColor
        self.developerProfile = developerProfile
    }

    public init(from dto: UserDTO) {
        self.id = dto.id
        self.username = dto.username
        self.displayName = dto.display_name
        self.role = dto.role
        self.phoneNumber = dto.phone_number
        self.avatarUrl = dto.avatar_url
        self.bio = dto.bio
        self.coverUrl = dto.cover_url
        self.borderTemplate = dto.border_template
        self.nameColor = dto.name_color
        self.developerProfile = dto.developer_profile
    }
}


public struct DeviceProfile: Codable, Equatable, Sendable {
    public let id: String
    public let deviceName: String
    public let identityKeyPub: String

    enum CodingKeys: String, CodingKey {
        case id
        case deviceName = "device_name"
        case identityKeyPub = "identity_key_pub"
    }

    public init(id: String, deviceName: String, identityKeyPub: String) {
        self.id = id
        self.deviceName = deviceName
        self.identityKeyPub = identityKeyPub
    }
}

extension Notification.Name {
    /// Posted when the server rejects the saved session (refresh token expired or revoked).
    public static let sessionExpired = Notification.Name("OurChat.sessionExpired")
}

public final class AppState: ObservableObject {
    @Published public var isInitialized: Bool = false
    @Published public var isAuthenticated: Bool = false
    @Published public var isBiometricLocked: Bool = false
    @Published public var selectedTab: AppTab = .chats
    @Published public var currentUser: UserProfile?
    @Published public var currentDevice: DeviceProfile?

    private var cancellables = Set<AnyCancellable>()

    /// - Parameter restoreSession: resume the session saved by an earlier launch, so the user only
    ///   logs in once (the app passes true; tests start from a clean state).
    public init(restoreSession: Bool = false) {
        if restoreSession {
            SessionStore.discardIfReinstalled()
            if let saved = SessionStore.load() {
                currentUser = saved.user
                currentDevice = saved.device
                isAuthenticated = true
            }
        }

        // The server rejected the saved session: back to the login screen
        NotificationCenter.default.publisher(for: .sessionExpired)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.logout() }
            .store(in: &cancellables)
    }

    public func setAuthenticated(user: UserProfile, device: DeviceProfile) {
        self.currentUser = user
        self.currentDevice = device
        self.isAuthenticated = true
        SessionStore.save(user: user, device: device)
    }

    public func updateCurrentUser(
        displayName: String? = nil,
        username: String? = nil,
        phoneNumber: String? = nil,
        avatarUrl: String? = nil,
        bio: String? = nil,
        coverUrl: String? = nil,
        borderTemplate: String? = nil,
        nameColor: String? = nil,
        developerProfile: DeveloperProfile? = nil
    ) {
        guard let current = currentUser else { return }
        let updated = UserProfile(
            id: current.id,
            username: username ?? current.username,
            displayName: displayName ?? current.displayName,
            role: current.role,
            phoneNumber: phoneNumber ?? current.phoneNumber,
            avatarUrl: avatarUrl ?? current.avatarUrl,
            bio: bio ?? current.bio,
            coverUrl: coverUrl ?? current.coverUrl,
            borderTemplate: borderTemplate ?? current.borderTemplate,
            nameColor: nameColor ?? current.nameColor,
            developerProfile: developerProfile ?? current.developerProfile
        )
        self.currentUser = updated
        if let device = currentDevice {
            SessionStore.save(user: updated, device: device)
        }
    }

    public func logout() {
        let loggedOutUserId = currentUser?.id
        RealtimeService.shared.stop()
        Task { @MainActor in
            await LiveLocationViewModel.shared.stopAfterSessionEnded(userId: loggedOutUserId)
            StoriesStore.shared.reset()
            BarkRelayManager.shared.reset()
        }
        SessionStore.clear()
        self.isAuthenticated = false
        self.currentUser = nil
        self.currentDevice = nil
        self.selectedTab = .chats
    }
}
