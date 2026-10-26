import Foundation
import UIKit
import UserNotifications

/// Alerts while Our Chat is closed, through the free Bark app.
///
/// iOS stops an app completely when it is swiped away, and Apple only delivers pushes to a closed
/// app signed by a paid developer account. Bark (App Store, free) is, so the server sends the alert
/// to the user's Bark key instead; tapping it opens Our Chat on that chat (`ourchat://chat/<id>`).
/// While the app is in the background with Bark on, the app stays quiet so nothing alerts twice.
@MainActor
public final class BarkRelayManager: ObservableObject {
    public static let shared = BarkRelayManager()

    public static let appStoreURL = URL(string: "https://apps.apple.com/app/id1403753865")!
    /// Our "ping" sound name in Bark once the user has imported ping.caf there
    public static let pingSoundName = "ping"

    public struct Settings: Decodable, Equatable, Sendable {
        public var configured: Bool
        public var enabled: Bool
        public var messageSound: String
        public var callSound: String
        public var language: String
        public var lastError: String?
        public var sounds: [String]

        enum CodingKeys: String, CodingKey {
            case configured, enabled, language, sounds
            case messageSound = "message_sound"
            case callSound = "call_sound"
            case lastError = "last_error"
        }
    }

    /// PATCH body; fields left nil are not sent (and not changed).
    private struct Changes: Encodable, Sendable {
        var enabled: Bool?
        var message_sound: String?
        var call_sound: String?
        var language: String?
    }

    @Published public private(set) var settings: Settings?
    @Published public private(set) var isBusy = false
    @Published public var errorMessage: String?
    @Published public var notice: String?
    @Published public private(set) var systemPermission: UNAuthorizationStatus = .notDetermined

    private nonisolated static let relayOnKey = "bark_relay_on"
    private static let promptShownKey = "bark_setup_prompt_shown"

    /// True when the server relays alerts to Bark for this user; the app then doesn't post its own
    /// banners while in the background. Readable from any thread (UserDefaults is thread-safe).
    public nonisolated static var isRelayOn: Bool {
        UserDefaults.standard.bool(forKey: relayOnKey)
    }

    /// The one-time "get alerts when Our Chat is closed" prompt has been shown.
    public static var setupPromptShown: Bool {
        get { UserDefaults.standard.bool(forKey: promptShownKey) }
        set { UserDefaults.standard.set(newValue, forKey: promptShownKey) }
    }

    private init() {}

    // MARK: - Our Chat's own notification permission

    public func refreshSystemPermission() async {
        systemPermission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Shows iOS's "Allow notifications?" popup (iOS only shows it once), or opens Settings if it was refused.
    public func requestSystemPermission() async {
        await refreshSystemPermission()
        if systemPermission == .denied {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                await UIApplication.shared.open(url)
            }
            return
        }
        _ = await PushNotificationManager.shared.requestAuthorization()
        await refreshSystemPermission()
    }

    // MARK: - Bark relay (server: /notifications/bark)

    public func refresh() async {
        do {
            var loaded: Settings = try await APIClient.shared.request(endpoint: "/notifications/bark")
            // Alerts are written in the app's language
            let language = LocalizationManager.shared.currentLanguage.rawValue
            if loaded.configured && loaded.language != language {
                loaded = try await APIClient.shared.request(
                    endpoint: "/notifications/bark",
                    method: "PATCH",
                    body: Changes(language: language)
                )
            }
            apply(loaded)
        } catch {
            // Keep the last known state (e.g. offline)
            print("[BarkRelayManager] Refresh failed: \(error.localizedDescription)")
        }
    }

    /// Saves the key from the Bark app. The server sends a test alert first and refuses a key Bark
    /// doesn't know, so success means the alert really reached Bark.
    @discardableResult
    public func connect(key: String) async -> Bool {
        struct Body: Encodable, Sendable {
            let key: String
            let language: String
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L("bark_error_empty_key")
            return false
        }
        return await perform {
            let saved: Settings = try await APIClient.shared.request(
                endpoint: "/notifications/bark",
                method: "PUT",
                body: Body(key: trimmed, language: LocalizationManager.shared.currentLanguage.rawValue)
            )
            self.apply(saved)
            self.notice = L("bark_notice_connected")
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        await update(Changes(enabled: enabled))
    }

    public func setMessageSound(_ sound: String) async {
        await update(Changes(message_sound: sound))
    }

    public func setCallSound(_ sound: String) async {
        await update(Changes(call_sound: sound))
    }

    public func sendTest() async {
        struct TestResult: Decodable, Sendable {
            let sent: Bool
        }
        await perform {
            let result: TestResult = try await APIClient.shared.request(endpoint: "/notifications/bark/test", method: "POST")
            await self.refresh() // picks up a key that was just switched off
            if result.sent {
                self.notice = L("bark_notice_test_sent")
            } else {
                self.errorMessage = self.lastErrorText ?? L("bark_error_unreachable")
            }
        }
    }

    public func disconnect() async {
        await perform {
            let cleared: Settings = try await APIClient.shared.request(endpoint: "/notifications/bark", method: "DELETE")
            self.apply(cleared)
        }
    }

    /// Why the last alert didn't arrive, in the user's words.
    public var lastErrorText: String? {
        switch settings?.lastError {
        case "key_rejected": return L("bark_error_key_rejected")
        case "unreachable": return L("bark_error_unreachable")
        default: return nil
        }
    }

    /// Before logging out (while still signed in): a logged-out phone must not keep getting this
    /// account's alerts. Best effort, at most 3 s, so logging out never hangs when offline.
    public func disconnectBeforeLogout() async {
        guard Self.isRelayOn || settings?.configured == true else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                let _: Settings? = try? await APIClient.shared.request(endpoint: "/notifications/bark", method: "DELETE")
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            await group.next()
            group.cancelAll()
        }
    }

    /// Logout: the next account must not inherit this one's relay state, and is offered Bark again.
    public func reset() {
        settings = nil
        errorMessage = nil
        notice = nil
        UserDefaults.standard.removeObject(forKey: Self.relayOnKey)
        UserDefaults.standard.removeObject(forKey: Self.promptShownKey)
    }

    private func update(_ changes: Changes) async {
        await perform {
            let updated: Settings = try await APIClient.shared.request(
                endpoint: "/notifications/bark",
                method: "PATCH",
                body: changes
            )
            self.apply(updated)
        }
    }

    @discardableResult
    private func perform(_ work: () async throws -> Void) async -> Bool {
        isBusy = true
        errorMessage = nil
        notice = nil
        defer { isBusy = false }
        do {
            try await work()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func apply(_ settings: Settings) {
        self.settings = settings
        UserDefaults.standard.set(settings.configured && settings.enabled, forKey: Self.relayOnKey)
    }
}
