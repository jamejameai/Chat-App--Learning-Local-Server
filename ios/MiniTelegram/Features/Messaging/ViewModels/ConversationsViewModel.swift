import Foundation
import SwiftUI
import Combine

@MainActor
public final class ConversationsViewModel: ObservableObject {
    @Published public var conversations: [ConversationItem] = []
    @Published public var searchQuery: String = ""
    @Published public var searchResults: [ChatMessage] = []
    @Published public var isLoading: Bool = false
    @Published public var teamMembers: [TeamMember] = []
    @Published public var isPresentingNewChat: Bool = false
    @Published public var errorMessage: String?

    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupSearchDebounce()
        setupRealtimeSubscriptions()
        loadLocalConversations()
    }

    public func loadLocalConversations() {
        self.conversations = LocalDatabaseManager.shared.getConversations()
    }

    public func refreshConversations() async {
        isLoading = true
        errorMessage = nil

        do {
            struct RawConversation: Codable {
                let id: String
                let type: String
                let title: String?
                let avatar_url: String?
                let last_message_at: String?
                let unread_count: String?
                let last_sequence_id: String?
                let is_pinned: Bool?
                let recipient_user_id: String?
                let recipient_role: String?
                let recipient_border_template: String?
                let recipient_name_color: String?
                let is_online: Bool?
                let last_seen: String?
                // Latest message (encrypted) for the preview line
                let last_message_sender_id: String?
                let last_message_envelope_type: String?
                let last_message_payload: String?
                let last_message_iv: String?
            }
            let myUserId = SessionStore.currentUserId

            /// "You: hi", "📷 Photo", "🎤 Voice message (3s)"... decrypted on this phone.
            func preview(for raw: RawConversation) -> String? {
                guard let payload = raw.last_message_payload, let iv = raw.last_message_iv else { return nil }
                let decrypted = MessageCryptoCoordinator.shared.decryptMessage(
                    conversationId: raw.id,
                    encryptedPayloadBase64: payload,
                    ivBase64: iv,
                    envelopeType: raw.last_message_envelope_type ?? "e2ee_text"
                )
                let body = MessagePreview.text(
                    text: decrypted.text,
                    attachment: decrypted.attachment,
                    voiceNote: decrypted.voiceNote
                )
                return raw.last_message_sender_id == myUserId ? "You: \(body)" : body
            }

            let rawList: [RawConversation] = try await APIClient.shared.request(
                endpoint: "/conversations",
                method: "GET",
                requiresAuth: true
            )

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let items: [ConversationItem] = rawList.map { raw in
                let timestamp = raw.last_message_at != nil ? dateFormatter.date(from: raw.last_message_at!) : nil
                let unread = Int(raw.unread_count ?? "0") ?? 0
                let seq = Int64(raw.last_sequence_id ?? "0") ?? 0
                let rawOnline = raw.is_online ?? false
                let lastSeenDate = raw.last_seen != nil ? dateFormatter.date(from: raw.last_seen!) : nil

                if let rId = raw.recipient_user_id {
                    PresenceManager.shared.recordInitialPresence(
                        userId: rId,
                        isOnline: rawOnline,
                        lastSeenAt: raw.last_seen
                    )
                }

                let effectiveOnline = PresenceManager.shared.isOnline(raw.recipient_user_id, fallback: rawOnline)

                return ConversationItem(
                    id: raw.id,
                    type: raw.type,
                    title: raw.title ?? "Conversation",
                    avatarUrl: raw.avatar_url,
                    lastMessageText: preview(for: raw),
                    lastMessageTimestamp: timestamp,
                    unreadCount: unread,
                    lastSequenceId: seq,
                    isPinned: raw.is_pinned ?? false,
                    isOnline: effectiveOnline,
                    lastSeen: lastSeenDate,
                    recipientUserId: raw.recipient_user_id,
                    recipientRole: raw.recipient_role,
                    recipientBorderTemplate: raw.recipient_border_template,
                    recipientNameColor: raw.recipient_name_color
                )
            }

            LocalDatabaseManager.shared.saveConversations(items)
            self.conversations = LocalDatabaseManager.shared.getConversations()
            isLoading = false
        } catch {
            isLoading = false
            // Keep local cached conversations on network error
            print("[ConversationsViewModel] refresh error: \(error.localizedDescription)")
        }
    }

    public func fetchTeamMembers() async {
        do {
            let list: [TeamMember] = try await APIClient.shared.request(
                endpoint: "/auth/users",
                method: "GET",
                requiresAuth: true
            )
            self.teamMembers = list
        } catch {
            print("[ConversationsViewModel] fetchTeamMembers error: \(error.localizedDescription)")
        }
    }

    public func createDirectConversation(recipientUserId: String, title: String) async -> ConversationItem? {
        isLoading = true
        errorMessage = nil

        struct CreateBody: Codable {
            let type: String
            let participant_user_ids: [String]
        }

        do {
            struct RawCreated: Codable {
                let id: String
                let type: String
                let title: String?
            }

            let res: RawCreated = try await APIClient.shared.request(
                endpoint: "/conversations",
                method: "POST",
                body: CreateBody(type: "direct", participant_user_ids: [recipientUserId]),
                requiresAuth: true
            )

            let item = ConversationItem(
                id: res.id,
                type: res.type,
                title: title,
                recipientUserId: recipientUserId
            )

            LocalDatabaseManager.shared.saveConversation(item)
            loadLocalConversations()
            isLoading = false
            return item
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.searchResults = []
                } else {
                    self.searchResults = LocalDatabaseManager.shared.searchMessages(query: query)
                }
            }
            .store(in: &cancellables)
    }

    private func setupRealtimeSubscriptions() {
        // RealtimeService has already saved the message; refresh the list (and fetch it from the
        // server if this is a chat we don't know yet, e.g. a new friend's first message)
        NotificationCenter.default.publisher(for: .chatMessageReceived)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let self, let message = note.object as? ChatMessage else { return }
                if LocalDatabaseManager.shared.getConversation(byId: message.conversationId) == nil {
                    Task { await self.refreshConversations() }
                } else {
                    self.loadLocalConversations()
                }
            }
            .store(in: &cancellables)

        // Catch up after the live connection comes back, the app returns to the foreground,
        // or someone adds me to a new group
        NotificationCenter.default.publisher(for: .realtimeReconnected)
            .merge(with: NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
            .merge(with: NotificationCenter.default.publisher(for: .conversationsChanged))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshConversations() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .presenceUpdated)
            .compactMap { $0.userInfo }
            .receive(on: RunLoop.main)
            .sink { [weak self] userInfo in
                guard let self = self,
                      let userId = userInfo["user_id"] as? String,
                      let isOnline = userInfo["is_online"] as? Bool else { return }
                for i in 0..<self.conversations.count {
                    if self.conversations[i].recipientUserId == userId {
                        self.conversations[i].isOnline = isOnline
                    }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .presenceSnapshotReceived)
            .compactMap { $0.userInfo?["online_user_ids"] as? [String] }
            .receive(on: RunLoop.main)
            .sink { [weak self] onlineIds in
                guard let self = self else { return }
                let set = Set(onlineIds)
                for i in 0..<self.conversations.count {
                    if let rId = self.conversations[i].recipientUserId {
                        if set.contains(rId) {
                            self.conversations[i].isOnline = true
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
}
