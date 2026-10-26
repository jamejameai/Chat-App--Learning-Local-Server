import Foundation
import SwiftUI
import Combine

@MainActor
public final class GroupsViewModel: ObservableObject {
    @Published public var groups: [ConversationItem] = []
    @Published public var searchText: String = ""
    @Published public var isLoading: Bool = false
    @Published public var isCreatingGroup: Bool = false
    @Published public var errorMessage: String? = nil

    public init() {
        loadGroups()
    }

    public var filteredGroups: [ConversationItem] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return groups
        }
        return groups.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    public func loadGroups() {
        let all = LocalDatabaseManager.shared.getConversations()
        self.groups = all.filter { $0.type == "group" }
    }

    public func syncGroups() async {
        isLoading = true
        errorMessage = nil

        struct ConversationDTO: Codable {
            let id: String
            let type: String
            let title: String
            let avatar_url: String?
            let last_sequence_id: String?
            let unread_count: String?
            let last_message_text: String?
            let last_message_at: String?
            let member_count: String?
        }

        do {
            let remote: [ConversationDTO] = try await APIClient.shared.request(
                endpoint: "/conversations",
                method: "GET",
                requiresAuth: true
            )

            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var items: [ConversationItem] = []
            for dto in remote where dto.type == "group" {
                let lastSeq = Int64(dto.last_sequence_id ?? "0") ?? 0
                let unread = Int(dto.unread_count ?? "0") ?? 0
                let mCount = Int(dto.member_count ?? "1") ?? 1
                let lastDate = dto.last_message_at != nil ? dateFormatter.date(from: dto.last_message_at!) : nil

                let item = ConversationItem(
                    id: dto.id,
                    type: "group",
                    title: dto.title,
                    avatarUrl: dto.avatar_url,
                    lastMessageText: dto.last_message_text,
                    lastMessageTimestamp: lastDate,
                    unreadCount: unread,
                    lastSequenceId: lastSeq,
                    memberCount: mCount
                )
                items.append(item)
            }

            LocalDatabaseManager.shared.saveConversations(items)
            loadGroups()
            isLoading = false
        } catch {
            isLoading = false
            print("[GroupsViewModel] syncGroups error: \(error.localizedDescription)")
        }
    }

    public func createGroup(title: String, memberUserIds: [String]) async -> ConversationItem? {
        isCreatingGroup = true
        errorMessage = nil

        struct CreateGroupBody: Codable {
            let type: String
            let title: String
            let participant_user_ids: [String]
        }

        struct CreateGroupResponse: Codable {
            let id: String
            let type: String
            let title: String
            let avatar_url: String?
            let created_at: String
        }

        do {
            let res: CreateGroupResponse = try await APIClient.shared.request(
                endpoint: "/conversations",
                method: "POST",
                body: CreateGroupBody(
                    type: "group",
                    title: title,
                    participant_user_ids: memberUserIds
                ),
                requiresAuth: true
            )

            let newGroup = ConversationItem(
                id: res.id,
                type: "group",
                title: res.title,
                avatarUrl: res.avatar_url,
                lastMessageText: "Group created",
                lastMessageTimestamp: Date(),
                unreadCount: 0,
                lastSequenceId: 0,
                memberCount: memberUserIds.count + 1
            )

            LocalDatabaseManager.shared.saveConversation(newGroup)
            loadGroups()
            isCreatingGroup = false
            return newGroup
        } catch {
            isCreatingGroup = false
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
