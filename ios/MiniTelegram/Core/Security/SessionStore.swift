import Foundation

/// Keeps the user logged in across app launches until they log out.
///
/// The account and device are stored in the Keychain next to the login tokens, so the whole
/// session lives and dies together. A session is only resumed when its refresh token is present.
public enum SessionStore {
    private static let userKey = "session_user"
    private static let deviceKey = "session_device"
    private static let accessTokenKey = "jwt_access_token"
    private static let refreshTokenKey = "jwt_refresh_token"
    private static let installMarkerKey = "ourchat_install_marker"

    public static func save(user: UserProfile, device: DeviceProfile) {
        guard let userData = try? JSONEncoder().encode(user),
              let deviceData = try? JSONEncoder().encode(device) else {
            return
        }
        try? KeychainManager.shared.save(key: userKey, data: userData)
        try? KeychainManager.shared.save(key: deviceKey, data: deviceData)
    }

    /// The saved session, or nil if there is none (or it can no longer be resumed).
    public static func load() -> (user: UserProfile, device: DeviceProfile)? {
        guard (try? KeychainManager.shared.getString(key: refreshTokenKey)) != nil,
              let userData = try? KeychainManager.shared.get(key: userKey),
              let deviceData = try? KeychainManager.shared.get(key: deviceKey),
              let user = try? JSONDecoder().decode(UserProfile.self, from: userData),
              let device = try? JSONDecoder().decode(DeviceProfile.self, from: deviceData) else {
            return nil
        }
        return (user, device)
    }

    /// The logged-in user's id, or nil when logged out.
    public static var currentUserId: String? {
        load()?.user.id
    }

    /// Forgets the session and its login tokens (logout, or the server rejected the session).
    public static func clear() {
        for key in [userKey, deviceKey, accessTokenKey, refreshTokenKey] {
            KeychainManager.shared.delete(key: key)
        }
    }

    /// iOS keeps Keychain items after an app is deleted. On the first launch of a fresh install
    /// (no marker in UserDefaults, which *is* deleted with the app) drop any session left behind.
    public static func discardIfReinstalled(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: installMarkerKey) else { return }
        clear()
        defaults.set(true, forKey: installMarkerKey)
    }
}
