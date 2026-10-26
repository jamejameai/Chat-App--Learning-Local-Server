import Foundation
import UIKit
import UserNotifications
import AudioToolbox

extension Notification.Name {
    /// Posted when the user taps a message notification; `object` is the conversation id to open.
    public static let openConversationRequested = Notification.Name("OurChat.openConversationRequested")
}

/// Tells the user about incoming messages, like Telegram:
/// - a banner with sound for a chat that is not on screen (or when the app is in the background),
/// - a short "received" sound for the chat that is open,
/// - a short "sent" sound when a message is sent.
/// Once a chat has been seen its notifications are removed and the app icon badge shows the unread count.
/// System sounds follow the phone's silent switch.
@MainActor
public final class MessageAlertManager {
    public static let shared = MessageAlertManager()

    /// The chat currently on screen (set by ChatDetailView). Its messages don't raise a banner.
    public var activeConversationId: String?
    /// Chat to open after a notification tap, kept until the chat list is ready (e.g. tap launched the app).
    public var pendingConversationId: String?

    private enum SystemSound {
        static let sent: SystemSoundID = 1004 // SentMessage
    }

    /// Our "ping" (Resources/Sounds/ping.caf): incoming messages and notifications.
    static let pingSoundName = UNNotificationSoundName("ping.caf")
    private lazy var pingSoundID: SystemSoundID = {
        var id: SystemSoundID = 1003 // system "received" sound if the file is missing
        if let url = Bundle.main.url(forResource: "ping", withExtension: "caf") {
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
        }
        return id
    }()

    private var observer: NSObjectProtocol?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    /// Begins listening for incoming messages and asks for notification permission (once).
    public func start() {
        guard observer == nil else { return }
        _ = PushNotificationManager.shared // installs the delegate that shows banners in the foreground

        observer = NotificationCenter.default.addObserver(
            forName: .chatMessageReceived,
            object: nil,
            queue: .main
        ) { note in
            guard let message = note.object as? ChatMessage else { return }
            MainActor.assumeIsolated {
                MessageAlertManager.shared.handleIncoming(message)
            }
        }

        Task {
            _ = await PushNotificationManager.shared.requestAuthorization()
        }
        updateBadge()
    }

    public func playSentSound() {
        AudioServicesPlaySystemSound(SystemSound.sent)
    }

    func handleIncoming(_ message: ChatMessage) {
        let isAppActive = UIApplication.shared.applicationState == .active
        if isAppActive && message.conversationId == activeConversationId {
            AudioServicesPlaySystemSound(pingSoundID)
        } else {
            postBanner(for: message)
        }
    }

    public func postBanner(for message: ChatMessage) {
        // In the background with Bark on, the server's Bark alert covers this message
        guard !Self.barkCoversBackgroundAlerts else { return }
        let content = UNMutableNotificationContent()
        // Sender's name (or the nickname you gave them) as the title
        content.title = ContactNicknames.displayName(userId: message.senderUserId, fallback: message.senderName)
        content.body = MessagePreview.text(text: message.text, attachment: message.attachment, voiceNote: message.voiceNote)
        content.sound = UNNotificationSound(named: Self.pingSoundName)
        content.threadIdentifier = message.conversationId
        content.userInfo = ["conversation_id": message.conversationId]
        content.badge = NSNumber(value: LocalDatabaseManager.shared.totalUnreadCount())

        // Message id as identifier: the same message never alerts twice
        let request = UNNotificationRequest(identifier: message.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// The chat has been seen: remove its notifications from the lock screen / Notification Center
    /// and bring the app icon badge down to the remaining unread count.
    public func clearNotifications(conversationId: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.deliveredNotifications()
                .filter { $0.request.content.threadIdentifier == conversationId }
                .map(\.request.identifier)
            if !ids.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
            updateBadge()
        }
    }

    /// True while the app is off screen and the server relays alerts to Bark (see BarkRelayManager):
    /// the app's own banner would then be a second alert for the same message.
    static var barkCoversBackgroundAlerts: Bool {
        BarkRelayManager.isRelayOn && UIApplication.shared.applicationState == .background
    }

    public func updateBadge() {
        UNUserNotificationCenter.current().setBadgeCount(LocalDatabaseManager.shared.totalUnreadCount())
    }

    /// iOS lets an app finish work for ~30 s after the user leaves it. Keep the live connection for
    /// that time (messages arriving right after switching away still raise a banner), and ask iOS to
    /// wake the app later for a background check.
    public func appDidEnterBackground() {
        BackgroundSyncManager.shared.scheduleNextBackgroundSync()
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "OurChat.keepAlive") {
            MainActor.assumeIsolated {
                MessageAlertManager.shared.endBackgroundTask()
            }
        }
    }

    public func appDidBecomeActive() {
        endBackgroundTask()
        updateBadge()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    static func previewText(for message: ChatMessage) -> String {
        if let voiceNote = message.voiceNote {
            return "🎤 Voice message (\(Int(voiceNote.durationSeconds))s)"
        }
        if let attachment = message.attachment {
            return "📎 \(attachment.fileName)"
        }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "New message" : text
    }
}
