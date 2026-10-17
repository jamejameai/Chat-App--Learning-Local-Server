import SwiftUI
import Combine

public enum AppTab: Hashable {
    case chats
    case calls
    case community
    case settings
}

public struct UserProfile: Codable, Equatable, Sendable {
    public let id: String
    public let username: String
    public let displayName: String
    public let role: String
    public let avatarUrl: String?

    public init(id: String, username: String, displayName: String, role: String, avatarUrl: String? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.role = role
        self.avatarUrl = avatarUrl
    }
}

public struct DeviceProfile: Codable, Equatable, Sendable {
    public let id: String
    public let deviceName: String
    public let identityKeyPub: String

    public init(id: String, deviceName: String, identityKeyPub: String) {
        self.id = id
        self.deviceName = deviceName
        self.identityKeyPub = identityKeyPub
    }
}

public final class AppState: ObservableObject {
    @Published public var isInitialized: Bool = false
    @Published public var isAuthenticated: Bool = false
    @Published public var isBiometricLocked: Bool = false
    @Published public var selectedTab: AppTab = .chats
    @Published public var currentUser: UserProfile?
    @Published public var currentDevice: DeviceProfile?

    public init() {}

    public func setAuthenticated(user: UserProfile, device: DeviceProfile) {
        self.currentUser = user
        self.currentDevice = device
        self.isAuthenticated = true
    }

    public func logout() {
        self.isAuthenticated = false
        self.currentUser = nil
        self.currentDevice = nil
        self.selectedTab = .chats
    }
}
