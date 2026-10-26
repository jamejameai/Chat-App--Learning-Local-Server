import Foundation
import BackgroundTasks

/// Background App Refresh: while the app is in the background (not swiped away), iOS wakes it from
/// time to time (iOS decides how often — typically every 15 minutes or more) to fetch new messages and
/// show notifications. Without Apple Push (needs a paid Apple Developer account) this is the only way to
/// alert while the app isn't open. iOS never wakes an app the user has swiped away.
public final class BackgroundSyncManager: @unchecked Sendable {
    public static let shared = BackgroundSyncManager()
    public static let taskId = "com.minitelegram.background-sync" // also in Info.plist

    @MainActor private var isSyncing: Bool = false

    // ISO8601DateFormatter is thread-safe; only used on the main actor anyway
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    /// Must run before the app finishes launching (MiniTelegramApp.init).
    @MainActor
    public func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundSyncManager.taskId,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            BackgroundSyncManager.shared.scheduleNextBackgroundSync()

            let work = Task { @MainActor in
                let newCount = await BackgroundSyncManager.shared.performCatchupSync(notify: true)
                print("[BackgroundSyncManager] Background sync completed with \(newCount) new messages")
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = {
                work.cancel()
            }
        }
    }

    public func scheduleNextBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundSyncManager.taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // iOS may run it later
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BackgroundSyncManager] Could not schedule background sync: \(error)")
        }
    }

    /// Downloads messages that arrived while the app was away. With `notify`, shows a notification for
    /// each new message from someone else that hasn't been read yet (e.g. not already read on another device).
    @MainActor
    @discardableResult
    public func performCatchupSync(notify: Bool) async -> Int {
        guard !isSyncing, let myUserId = SessionStore.currentUserId else { return 0 }
        isSyncing = true
        defer { isSyncing = false }

        let lastReadByConversation = await refreshConversationList()
        var unseen: [ChatMessage] = []

        struct SyncResponse: Codable {
            struct RawMsg: Codable {
                let id: String
                let sender_user_id: String
                let sender_device_id: String?
                let sender_username: String?
                let sender_display_name: String?
                let sequence_id: String
                let envelope_type: String
                let encrypted_payload: String
                let iv: String
                let reply_to_message_id: String?
                let created_at: String
            }
            let conversation_id: String
            let messages: [RawMsg]
            let latest_sequence_id: FlexibleInt64
            let read_up_to_sequence_id: FlexibleInt64?
            let has_more: Bool
        }

        for conv in LocalDatabaseManager.shared.getConversations() {
            let sinceSequence = LocalDatabaseManager.shared.latestStoredSequenceId(conversationId: conv.id)
            do {
                let res: SyncResponse = try await APIClient.shared.request(
                    endpoint: "/conversations/\(conv.id)/sync?since_sequence=\(sinceSequence)&limit=50"
                )

                let lastRead = lastReadByConversation[conv.id] ?? 0
                for raw in res.messages {
                    let decrypted = MessageCryptoCoordinator.shared.decryptMessage(
                        conversationId: conv.id,
                        encryptedPayloadBase64: raw.encrypted_payload,
                        ivBase64: raw.iv,
                        envelopeType: raw.envelope_type
                    )
                    let isMine = raw.sender_user_id == myUserId
                    let sequenceId = Int64(raw.sequence_id) ?? 0
                    let message = ChatMessage(
                        id: raw.id,
                        conversationId: conv.id,
                        senderUserId: raw.sender_user_id,
                        senderDeviceId: raw.sender_device_id ?? "",
                        senderName: raw.sender_display_name ?? raw.sender_username ?? "Friend",
                        sequenceId: sequenceId,
                        text: decrypted.text,
                        replyToMessageId: raw.reply_to_message_id ?? decrypted.replyToMessageId,
                        status: isMine ? .sent : .delivered,
                        timestamp: Self.isoFormatter.date(from: raw.created_at) ?? Date(),
                        isOutgoing: isMine,
                        attachment: decrypted.attachment,
                        voiceNote: decrypted.voiceNote
                    )

                    let isNew = !LocalDatabaseManager.shared.hasMessage(id: raw.id, conversationId: conv.id)
                    LocalDatabaseManager.shared.saveMessage(message)
                    if isNew && !isMine && sequenceId > lastRead {
                        unseen.append(message)
                    }
                }

                LocalDatabaseManager.shared.markOutgoingRead(
                    conversationId: conv.id,
                    upToSequence: res.read_up_to_sequence_id?.value ?? 0
                )
            } catch {
                print("[BackgroundSyncManager] Sync failed for conversation \(conv.id): \(error.localizedDescription)")
            }
        }

        if notify {
            for message in unseen.suffix(10) { // a long backlog shouldn't flood the lock screen
                MessageAlertManager.shared.postBanner(for: message)
            }
        }
        MessageAlertManager.shared.updateBadge()
        return unseen.count
    }

    /// Adds chats that exist on the server but not on this phone (e.g. a new friend's first message)
    /// and returns how far I've read each chat, so messages already read elsewhere don't alert.
    @MainActor
    private func refreshConversationList() async -> [String: Int64] {
        struct RawConversation: Codable {
            let id: String
            let type: String
            let title: String?
            let avatar_url: String?
            let last_read_sequence_id: String?
            let recipient_user_id: String?
        }
        guard let list: [RawConversation] = try? await APIClient.shared.request(endpoint: "/conversations") else {
            return [:]
        }

        var lastRead: [String: Int64] = [:]
        for raw in list {
            lastRead[raw.id] = Int64(raw.last_read_sequence_id ?? "0") ?? 0
            if LocalDatabaseManager.shared.getConversation(byId: raw.id) == nil {
                LocalDatabaseManager.shared.saveConversation(ConversationItem(
                    id: raw.id,
                    type: raw.type,
                    title: raw.title ?? "Chat",
                    avatarUrl: raw.avatar_url,
                    recipientUserId: raw.recipient_user_id
                ))
            }
        }
        return lastRead
    }
}
