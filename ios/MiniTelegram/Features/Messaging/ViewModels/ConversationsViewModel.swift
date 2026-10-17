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

                return ConversationItem(
                    id: raw.id,
                    type: raw.type,
                    title: raw.title ?? "Conversation",
                    avatarUrl: raw.avatar_url,
                    lastMessageTimestamp: timestamp,
                    unreadCount: unread,
                    lastSequenceId: seq,
                    isPinned: raw.is_pinned ?? false,
                    recipientUserId: raw.recipient_user_id
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
        RealtimeService.shared.onMessageReceived = { [weak self] message in
            Task { @MainActor in
                LocalDatabaseManager.shared.saveMessage(message)
                self?.loadLocalConversations()
            }
        }

        RealtimeService.shared.onPresenceUpdate = { [weak self] userId, isOnline in
            Task { @MainActor in
                guard let self = self else { return }
                for i in 0..<self.conversations.count {
                    if self.conversations[i].recipientUserId == userId {
                        self.conversations[i].isOnline = isOnline
                    }
                }
            }
        }
    }
}
