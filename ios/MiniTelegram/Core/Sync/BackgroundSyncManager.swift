import Foundation
import BackgroundTasks

public final class BackgroundSyncManager: @unchecked Sendable {
    public static let shared = BackgroundSyncManager()
    public static let taskId = "com.minitelegram.background-sync"

    private var isSyncing: Bool = false

    private init() {}

    @MainActor
    public func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundSyncManager.taskId,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            self?.scheduleNextBackgroundSync()

            Task {
                let newCount = await self?.performCatchupSync() ?? 0
                print("[BackgroundSyncManager] Background sync completed with \(newCount) new messages")
                refreshTask.setTaskCompleted(success: true)
            }

            refreshTask.expirationHandler = {
                print("[BackgroundSyncManager] Task expired")
            }
        }
    }

    public func scheduleNextBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundSyncManager.taskId)
        // Request sync every 15 minutes while idle/charging
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[BackgroundSyncManager] Scheduled background sync successfully")
        } catch {
            print("[BackgroundSyncManager] Could not schedule background sync: \(error)")
        }
    }

    public func performCatchupSync() async -> Int {
        if isSyncing { return 0 }
        isSyncing = true
        defer { isSyncing = false }

        let conversations = LocalDatabaseManager.shared.getConversations()
        var totalNewMessages = 0

        struct SyncResponse: Codable {
            struct RawMsg: Codable {
                let id: String
                let sender_user_id: String
                let sender_device_id: String?
                let sender_username: String?
                let sequence_id: String
                let envelope_type: String
                let encrypted_payload: String
                let iv: String
                let reply_to_message_id: String?
                let created_at: String
            }
            let conversation_id: String
            let messages: [RawMsg]
            let latest_sequence_id: Int64
            let has_more: Bool
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for conv in conversations {
            let endpoint = "/conversations/\(conv.id)/sync?since_sequence=\(conv.lastSequenceId)&limit=50"
            do {
                let res: SyncResponse = try await APIClient.shared.request(
                    endpoint: endpoint,
                    method: "GET",
                    requiresAuth: true
                )

                var newMessages: [ChatMessage] = []
                for raw in res.messages {
                    let decrypted = MessageCryptoCoordinator.shared.decryptMessage(
                        conversationId: conv.id,
                        encryptedPayloadBase64: raw.encrypted_payload,
                        ivBase64: raw.iv,
                        envelopeType: raw.envelope_type
                    )

                    let seq = Int64(raw.sequence_id) ?? 0
                    let timestamp = dateFormatter.date(from: raw.created_at) ?? Date()

                    let msg = ChatMessage(
                        id: raw.id,
                        conversationId: conv.id,
                        senderUserId: raw.sender_user_id,
                        senderDeviceId: raw.sender_device_id ?? "",
                        senderName: raw.sender_username ?? "Team Member",
                        sequenceId: seq,
                        text: decrypted.text,
                        replyToMessageId: raw.reply_to_message_id ?? decrypted.replyToMessageId,
                        status: .read,
                        timestamp: timestamp,
                        isOutgoing: false,
                        attachment: decrypted.attachment,
                        voiceNote: decrypted.voiceNote
                    )
                    newMessages.append(msg)
                }

                if !newMessages.isEmpty {
                    LocalDatabaseManager.shared.saveMessages(newMessages, for: conv.id)
                    totalNewMessages += newMessages.count
                }
            } catch {
                print("[BackgroundSyncManager] Sync failed for conversation \(conv.id): \(error)")
            }
        }

        return totalNewMessages
    }
}
