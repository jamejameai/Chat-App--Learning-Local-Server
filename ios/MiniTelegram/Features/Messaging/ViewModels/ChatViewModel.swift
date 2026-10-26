import Foundation
import SwiftUI
import Combine

@MainActor
public final class ChatViewModel: ObservableObject {
    public let conversation: ConversationItem
    @Published public var messages: [ChatMessage] = []
    @Published public var inputText: String = ""
    @Published public var replyingToMessage: ChatMessage?
    @Published public var isPeerTyping: Bool = false
    @Published public var peerTypingName: String = ""
    @Published public var isLoadingMore: Bool = false

    private var typingTimer: Timer?
    private var isCurrentlyTyping: Bool = false
    private var cancellables = Set<AnyCancellable>()

    public init(conversation: ConversationItem) {
        self.conversation = conversation
        loadLocalMessages()
        setupRealtime()
    }

    public func loadLocalMessages() {
        self.messages = LocalDatabaseManager.shared.getMessages(conversationId: conversation.id)
        LocalDatabaseManager.shared.markConversationRead(conversationId: conversation.id)

        // On screen = seen: drop this chat's notifications (only while the app is really open,
        // so a banner shown while in the background is not removed straight away)
        if UIApplication.shared.applicationState == .active {
            MessageAlertManager.shared.clearNotifications(conversationId: conversation.id)
        }
    }

    public func syncMessages() async {
        let lastSeq = LocalDatabaseManager.shared.latestStoredSequenceId(conversationId: conversation.id)
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
            /// How far the other members have read (drives "Seen" on my messages)
            let read_up_to_sequence_id: FlexibleInt64?
            let has_more: Bool
        }
        let myUserId = SessionStore.currentUserId

        do {
            let res: SyncResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversation.id)/sync?since_sequence=\(lastSeq)&limit=50",
                method: "GET",
                requiresAuth: true
            )

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var newChatMessages: [ChatMessage] = []
            for raw in res.messages {
                let decrypted = MessageCryptoCoordinator.shared.decryptMessage(
                    conversationId: conversation.id,
                    encryptedPayloadBase64: raw.encrypted_payload,
                    ivBase64: raw.iv,
                    envelopeType: raw.envelope_type
                )

                let seq = Int64(raw.sequence_id) ?? 0
                let timestamp = dateFormatter.date(from: raw.created_at) ?? Date()

                // Mine (e.g. sent from another device) or theirs. Theirs arrive as "delivered", so viewing
                // them sends a read receipt and the sender sees "Seen".
                let isMine = myUserId != nil && raw.sender_user_id == myUserId
                let msg = ChatMessage(
                    id: raw.id,
                    conversationId: conversation.id,
                    senderUserId: raw.sender_user_id,
                    senderDeviceId: raw.sender_device_id ?? "",
                    senderName: raw.sender_display_name ?? raw.sender_username ?? "Friend",
                    sequenceId: seq,
                    text: decrypted.text,
                    replyToMessageId: raw.reply_to_message_id ?? decrypted.replyToMessageId,
                    status: isMine ? .sent : .delivered,
                    timestamp: timestamp,
                    isOutgoing: isMine,
                    attachment: decrypted.attachment,
                    voiceNote: decrypted.voiceNote
                )
                newChatMessages.append(msg)
            }

            LocalDatabaseManager.shared.saveMessages(newChatMessages, for: conversation.id)
            LocalDatabaseManager.shared.markOutgoingRead(
                conversationId: conversation.id,
                upToSequence: res.read_up_to_sequence_id?.value ?? 0
            )
            loadLocalMessages()

            // More than one page missed: keep going (the cursor advances with every saved page)
            if res.has_more, !newChatMessages.isEmpty {
                await syncMessages()
            }
        } catch {
            print("[ChatViewModel] syncMessages error: \(error.localizedDescription)")
        }
    }

    public func sendMessage(currentUserId: String, currentUsername: String) async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Lowercase: the server stores ids as UUIDs and returns them lowercase; matching case keeps
        // one local copy per message (sync, receipts and "Seen" all match by id)
        let messageId = UUID().uuidString.lowercased()
        let replyId = replyingToMessage?.id
        let replyPreview = replyingToMessage?.text

        // 1. Optimistic local message insertion
        let optimisticMessage = ChatMessage(
            id: messageId,
            conversationId: conversation.id,
            senderUserId: currentUserId,
            senderName: currentUsername,
            text: trimmed,
            replyToMessageId: replyId,
            replyPreview: replyPreview,
            status: .sending,
            timestamp: Date(),
            isOutgoing: true
        )

        LocalDatabaseManager.shared.saveMessage(optimisticMessage)
        loadLocalMessages()

        // Clear composer state immediately
        inputText = ""
        replyingToMessage = nil
        notifyTyping(isTyping: false)

        // 2. Encrypt message envelope
        do {
            let (payload, iv, _) = try MessageCryptoCoordinator.shared.encryptMessage(
                conversationId: conversation.id,
                text: trimmed,
                replyToMessageId: replyId,
                isGroup: conversation.type == "group"
            )

            struct SubmitBody: Codable {
                let id: String
                let envelope_type: String
                let encrypted_payload: String
                let iv: String
                let reply_to_message_id: String?
            }

            struct SubmitResponse: Codable {
                let id: String
                let sequence_id: FlexibleInt64
                let status: String
                let deduplicated: Bool
            }

            let res: SubmitResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversation.id)/messages",
                method: "POST",
                body: SubmitBody(
                    id: messageId,
                    envelope_type: "e2ee_text", // wire kind the server accepts; crypto scheme is auto-detected on receive
                    encrypted_payload: payload,
                    iv: iv,
                    reply_to_message_id: replyId
                ),
                requiresAuth: true
            )

            // 3. Update status to sent with sequence ID
            var updated = optimisticMessage
            updated.status = .sent
            updated.sequenceId = res.sequence_id.value
            LocalDatabaseManager.shared.saveMessage(updated)
            loadLocalMessages()
            MessageAlertManager.shared.playSentSound()
        } catch {
            print("[ChatViewModel] sendMessage error: \(error.localizedDescription)")
            LocalDatabaseManager.shared.updateMessageStatus(
                messageId: messageId,
                conversationId: conversation.id,
                status: .failed
            )
            loadLocalMessages()
        }
    }

    public func sendAttachment(
        fileURL: URL,
        fileName: String,
        mimeType: String,
        currentUserId: String,
        currentUsername: String
    ) async {
        // Lowercase: the server stores ids as UUIDs and returns them lowercase; matching case keeps
        // one local copy per message (sync, receipts and "Seen" all match by id)
        let messageId = UUID().uuidString.lowercased()
        let replyId = replyingToMessage?.id
        let replyPreview = replyingToMessage?.text
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

        // 1. Optimistic message
        let optimisticAttachment = MessageAttachment(
            id: UUID().uuidString,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: fileSize,
            keyBase64: "",
            ivBase64: "",
            sha256Checksum: "",
            downloadUrl: "",
            localDecryptedPath: fileURL.path
        )

        let optimisticMessage = ChatMessage(
            id: messageId,
            conversationId: conversation.id,
            senderUserId: currentUserId,
            senderName: currentUsername,
            text: "",
            replyToMessageId: replyId,
            replyPreview: replyPreview,
            status: .sending,
            timestamp: Date(),
            isOutgoing: true,
            attachment: optimisticAttachment
        )

        LocalDatabaseManager.shared.saveMessage(optimisticMessage)
        loadLocalMessages()
        replyingToMessage = nil

        do {
            // 2. Encrypt & Upload attachment
            let (attId, keyBase64, ivBase64, sha256, downloadUrl) = try await AttachmentManager.shared.encryptAndUploadFile(
                fileURL: fileURL,
                fileName: fileName,
                mimeType: mimeType
            )

            let finalAttachment = MessageAttachment(
                id: attId,
                fileName: fileName,
                mimeType: mimeType,
                byteSize: fileSize,
                keyBase64: keyBase64,
                ivBase64: ivBase64,
                sha256Checksum: sha256,
                downloadUrl: downloadUrl,
                localDecryptedPath: fileURL.path
            )

            // 3. Encrypt message envelope with attachment
            let (payload, iv, _) = try MessageCryptoCoordinator.shared.encryptMessage(
                conversationId: conversation.id,
                text: "",
                replyToMessageId: replyId,
                attachment: finalAttachment,
                isGroup: conversation.type == "group"
            )

            struct SubmitBody: Codable {
                let id: String
                let envelope_type: String
                let encrypted_payload: String
                let iv: String
                let reply_to_message_id: String?
            }

            struct SubmitResponse: Codable {
                let id: String
                let sequence_id: FlexibleInt64
                let status: String
                let deduplicated: Bool
            }

            let res: SubmitResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversation.id)/messages",
                method: "POST",
                body: SubmitBody(
                    id: messageId,
                    envelope_type: "e2ee_attachment", // wire kind the server accepts; crypto scheme is auto-detected on receive
                    encrypted_payload: payload,
                    iv: iv,
                    reply_to_message_id: replyId
                ),
                requiresAuth: true
            )

            var updated = optimisticMessage
            updated.attachment = finalAttachment
            updated.status = .sent
            updated.sequenceId = res.sequence_id.value
            LocalDatabaseManager.shared.saveMessage(updated)
            loadLocalMessages()
        } catch {
            print("[ChatViewModel] sendAttachment error: \(error.localizedDescription)")
            LocalDatabaseManager.shared.updateMessageStatus(
                messageId: messageId,
                conversationId: conversation.id,
                status: .failed
            )
            loadLocalMessages()
        }
    }

    public func sendVoiceNote(
        fileURL: URL,
        duration: TimeInterval,
        waveform: [Float],
        currentUserId: String,
        currentUsername: String
    ) async {
        // Lowercase: the server stores ids as UUIDs and returns them lowercase; matching case keeps
        // one local copy per message (sync, receipts and "Seen" all match by id)
        let messageId = UUID().uuidString.lowercased()
        let replyId = replyingToMessage?.id
        let replyPreview = replyingToMessage?.text
        let voiceMetadata = VoiceNoteMetadata(durationSeconds: duration, waveformSamples: waveform)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

        let optimisticAttachment = MessageAttachment(
            id: UUID().uuidString,
            fileName: "voice_\(Date().timeIntervalSince1970).m4a",
            mimeType: "audio/m4a",
            byteSize: fileSize,
            keyBase64: "",
            ivBase64: "",
            sha256Checksum: "",
            downloadUrl: "",
            localDecryptedPath: fileURL.path
        )

        let optimisticMessage = ChatMessage(
            id: messageId,
            conversationId: conversation.id,
            senderUserId: currentUserId,
            senderName: currentUsername,
            text: "",
            replyToMessageId: replyId,
            replyPreview: replyPreview,
            status: .sending,
            timestamp: Date(),
            isOutgoing: true,
            attachment: optimisticAttachment,
            voiceNote: voiceMetadata
        )

        LocalDatabaseManager.shared.saveMessage(optimisticMessage)
        loadLocalMessages()
        replyingToMessage = nil

        do {
            let (attId, keyBase64, ivBase64, sha256, downloadUrl) = try await AttachmentManager.shared.encryptAndUploadFile(
                fileURL: fileURL,
                fileName: optimisticAttachment.fileName,
                mimeType: "audio/m4a"
            )

            let finalAttachment = MessageAttachment(
                id: attId,
                fileName: optimisticAttachment.fileName,
                mimeType: "audio/m4a",
                byteSize: fileSize,
                keyBase64: keyBase64,
                ivBase64: ivBase64,
                sha256Checksum: sha256,
                downloadUrl: downloadUrl,
                localDecryptedPath: fileURL.path
            )

            let (payload, iv, _) = try MessageCryptoCoordinator.shared.encryptMessage(
                conversationId: conversation.id,
                text: "",
                replyToMessageId: replyId,
                attachment: finalAttachment,
                voiceNote: voiceMetadata,
                isGroup: conversation.type == "group"
            )

            struct SubmitBody: Codable {
                let id: String
                let envelope_type: String
                let encrypted_payload: String
                let iv: String
                let reply_to_message_id: String?
            }

            struct SubmitResponse: Codable {
                let id: String
                let sequence_id: FlexibleInt64
                let status: String
                let deduplicated: Bool
            }

            let res: SubmitResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversation.id)/messages",
                method: "POST",
                body: SubmitBody(
                    id: messageId,
                    envelope_type: "e2ee_voice", // wire kind the server accepts; crypto scheme is auto-detected on receive
                    encrypted_payload: payload,
                    iv: iv,
                    reply_to_message_id: replyId
                ),
                requiresAuth: true
            )

            var updated = optimisticMessage
            updated.attachment = finalAttachment
            updated.status = .sent
            updated.sequenceId = res.sequence_id.value
            LocalDatabaseManager.shared.saveMessage(updated)
            loadLocalMessages()
        } catch {
            print("[ChatViewModel] sendVoiceNote error: \(error.localizedDescription)")
            LocalDatabaseManager.shared.updateMessageStatus(
                messageId: messageId,
                conversationId: conversation.id,
                status: .failed
            )
            loadLocalMessages()
        }
    }

    public func toggleReaction(message: ChatMessage, emoji: String, currentUserId: String) {
        LocalDatabaseManager.shared.toggleReaction(
            messageId: message.id,
            conversationId: conversation.id,
            emoji: emoji,
            userId: currentUserId
        )
        loadLocalMessages()
    }

    public func markDeliveredOrRead(message: ChatMessage, status: MessageDeliveryStatus) {
        guard !message.isOutgoing && message.status != status else { return }

        Task {
            struct ReceiptBody: Codable {
                let status: String
            }
            do {
                let _: [String: String] = try await APIClient.shared.request(
                    endpoint: "/conversations/\(conversation.id)/messages/\(message.id)/receipt",
                    method: "POST",
                    body: ReceiptBody(status: status.rawValue),
                    requiresAuth: true
                )
                LocalDatabaseManager.shared.updateMessageStatus(
                    messageId: message.id,
                    conversationId: conversation.id,
                    status: status
                )
            } catch {
                // Receipt send retry later
            }
        }
    }

    public func handleInputChanged(_ text: String) {
        if !text.isEmpty && !isCurrentlyTyping {
            isCurrentlyTyping = true
            notifyTyping(isTyping: true)
        }

        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isCurrentlyTyping = false
                self?.notifyTyping(isTyping: false)
            }
        }
    }

    private func notifyTyping(isTyping: Bool) {
        RealtimeService.shared.sendTyping(conversationId: conversation.id, isTyping: isTyping)
    }

    private func setupRealtime() {
        RealtimeService.shared.joinConversation(conversationId: conversation.id)

        // Live messages for this chat (RealtimeService has already saved them)
        NotificationCenter.default.publisher(for: .chatMessageReceived)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self,
                      let message = note.object as? ChatMessage,
                      message.conversationId == self.conversation.id else { return }
                self.loadLocalMessages()
            }
            .store(in: &cancellables)

        // The other person saw my messages ("Seen")
        NotificationCenter.default.publisher(for: .messageStatusChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self, (note.object as? String) == self.conversation.id else { return }
                self.loadLocalMessages()
            }
            .store(in: &cancellables)

        // Fetch anything missed while the connection was down or the app was in the background
        NotificationCenter.default.publisher(for: .realtimeReconnected)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.syncMessages() }
            }
            .store(in: &cancellables)

        RealtimeService.shared.onReceiptReceived = { [weak self] msgId, convId, status in
            guard let self = self, convId == self.conversation.id else { return }
            Task { @MainActor in
                LocalDatabaseManager.shared.updateMessageStatus(
                    messageId: msgId,
                    conversationId: convId,
                    status: status
                )
                self.loadLocalMessages()
            }
        }

        RealtimeService.shared.onTypingUpdate = { [weak self] convId, userId, isTyping in
            guard let self = self, convId == self.conversation.id else { return }
            Task { @MainActor in
                self.isPeerTyping = isTyping
                self.peerTypingName = self.conversation.title
            }
        }
    }
}
