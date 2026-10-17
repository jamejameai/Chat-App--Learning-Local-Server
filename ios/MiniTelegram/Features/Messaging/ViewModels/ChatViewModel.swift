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

    public init(conversation: ConversationItem) {
        self.conversation = conversation
        loadLocalMessages()
        setupRealtime()
    }

    public func loadLocalMessages() {
        self.messages = LocalDatabaseManager.shared.getMessages(conversationId: conversation.id)
        LocalDatabaseManager.shared.markConversationRead(conversationId: conversation.id)
    }

    public func syncMessages() async {
        let lastSeq = conversation.lastSequenceId
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
                let text = MessageCryptoCoordinator.shared.decryptMessage(
                    conversationId: conversation.id,
                    encryptedPayloadBase64: raw.encrypted_payload,
                    ivBase64: raw.iv,
                    envelopeType: raw.envelope_type
                )

                let seq = Int64(raw.sequence_id) ?? 0
                let timestamp = dateFormatter.date(from: raw.created_at) ?? Date()

                let msg = ChatMessage(
                    id: raw.id,
                    conversationId: conversation.id,
                    senderUserId: raw.sender_user_id,
                    senderDeviceId: raw.sender_device_id ?? "",
                    senderName: raw.sender_username ?? "Team Member",
                    sequenceId: seq,
                    text: text,
                    replyToMessageId: raw.reply_to_message_id,
                    status: .read,
                    timestamp: timestamp,
                    isOutgoing: false
                )
                newChatMessages.append(msg)
            }

            LocalDatabaseManager.shared.saveMessages(newChatMessages, for: conversation.id)
            loadLocalMessages()
        } catch {
            print("[ChatViewModel] syncMessages error: \(error.localizedDescription)")
        }
    }

    public func sendMessage(currentUserId: String, currentUsername: String) async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let messageId = UUID().uuidString
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
            let (payload, iv, envType) = try MessageCryptoCoordinator.shared.encryptMessage(
                conversationId: conversation.id,
                text: trimmed,
                replyToMessageId: replyId
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
                let sequence_id: Int64
                let status: String
                let deduplicated: Bool
            }

            let res: SubmitResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversation.id)/messages",
                method: "POST",
                body: SubmitBody(
                    id: messageId,
                    envelope_type: envType,
                    encrypted_payload: payload,
                    iv: iv,
                    reply_to_message_id: replyId
                ),
                requiresAuth: true
            )

            // 3. Update status to sent with sequence ID
            var updated = optimisticMessage
            updated.status = .sent
            updated.sequenceId = res.sequence_id
            LocalDatabaseManager.shared.saveMessage(updated)
            loadLocalMessages()
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
