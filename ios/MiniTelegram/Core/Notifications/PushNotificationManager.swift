import Foundation
import UserNotifications
import UIKit

public final class PushNotificationManager: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    public static let shared = PushNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private var apnsTokenHex: String?

    private override init() {
        super.init()
        center.delegate = self
    }

    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return granted
        } catch {
            print("[PushNotificationManager] Authorization failed: \(error)")
            return false
        }
    }

    public func setDeviceToken(_ tokenData: Data, deviceId: String) {
        let tokenHex = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        self.apnsTokenHex = tokenHex

        Task {
            struct RegisterBody: Codable {
                let apns_token: String
                let device_id: String
            }

            do {
                let _: [String: String] = try await APIClient.shared.request(
                    endpoint: "/notifications/token",
                    method: "POST",
                    body: RegisterBody(apns_token: tokenHex, device_id: deviceId),
                    requiresAuth: true
                )
                print("[PushNotificationManager] Successfully registered APNs token with backend")
            } catch {
                print("[PushNotificationManager] Failed to register token: \(error)")
            }
        }
    }

    public func handleRemoteNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard let data = userInfo["data"] as? [String: Any],
              let convId = data["conversation_id"] as? String,
              let ciphertext = data["encrypted_payload"] as? String,
              let iv = data["iv"] as? String,
              let envType = data["envelope_type"] as? String else {
            return false
        }

        // 1. Decrypt zero-knowledge message offline using local cryptographic ratchet
        let decrypted = MessageCryptoCoordinator.shared.decryptMessage(
            conversationId: convId,
            encryptedPayloadBase64: ciphertext,
            ivBase64: iv,
            envelopeType: envType
        )

        let seqNum = (data["sequence_id"] as? NSNumber)?.int64Value ?? 0
        let msgId = (data["message_id"] as? String) ?? UUID().uuidString

        // 2. Persist to local database
        let msg = ChatMessage(
            id: msgId,
            conversationId: convId,
            senderUserId: "",
            senderName: "Mini Telegram",
            sequenceId: seqNum,
            text: decrypted.text,
            replyToMessageId: decrypted.replyToMessageId,
            status: .delivered,
            timestamp: Date(),
            isOutgoing: false,
            attachment: decrypted.attachment,
            voiceNote: decrypted.voiceNote
        )
        LocalDatabaseManager.shared.saveMessage(msg)

        // 3. Present local notification with decrypted content
        let content = UNMutableNotificationContent()
        content.title = "New Encrypted Message"
        content.body = decrypted.text.isEmpty ? "New message received" : decrypted.text
        content.sound = .default
        content.badge = NSNumber(value: 1)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: msgId, content: content, trigger: trigger)
        center.add(request)

        return true
    }

    // MARK: - UNUserNotificationCenterDelegate
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even if app is in foreground
        completionHandler([.banner, .badge, .sound])
    }

    /// Tapping a message notification opens that chat.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let conversationId = response.notification.request.content.userInfo["conversation_id"] as? String {
            DispatchQueue.main.async {
                // Kept until the chat list exists (the tap may have launched the app)
                MainActor.assumeIsolated {
                    MessageAlertManager.shared.pendingConversationId = conversationId
                }
                NotificationCenter.default.post(name: .openConversationRequested, object: conversationId)
            }
        }
        completionHandler()
    }
}
