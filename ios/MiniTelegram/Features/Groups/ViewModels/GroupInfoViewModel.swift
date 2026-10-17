import Foundation
import SwiftUI
import Combine

@MainActor
public final class GroupInfoViewModel: ObservableObject {
    public let conversationId: String
    @Published public var conversationTitle: String
    @Published public var members: [GroupMember] = []
    @Published public var currentUserRole: String = "member"
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    private var cancellables = Set<AnyCancellable>()

    public init(conversation: ConversationItem) {
        self.conversationId = conversation.id
        self.conversationTitle = conversation.title
        setupRealtime()
    }

    public var isOwner: Bool {
        currentUserRole == "owner"
    }

    public var isAdmin: Bool {
        currentUserRole == "admin" || currentUserRole == "owner"
    }

    public func fetchDetails(currentUserId: String) async {
        isLoading = true
        errorMessage = nil

        struct MemberDTO: Codable {
            let id: String
            let username: String
            let display_name: String?
            let avatar_url: String?
            let role: String
            let joined_at: String?
        }

        struct ConversationDetailResponse: Codable {
            let id: String
            let type: String
            let title: String
            let avatar_url: String?
            let members: [MemberDTO]?
        }

        do {
            let res: ConversationDetailResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversationId)",
                method: "GET",
                requiresAuth: true
            )

            self.conversationTitle = res.title
            if let dtos = res.members {
                self.members = dtos.map { dto in
                    GroupMember(
                        id: dto.id,
                        username: dto.username,
                        displayName: dto.display_name,
                        avatarUrl: dto.avatar_url,
                        role: dto.role,
                        joinedAt: dto.joined_at
                    )
                }

                if let current = self.members.first(where: { $0.id == currentUserId }) {
                    self.currentUserRole = current.role
                }
            }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            print("[GroupInfoViewModel] fetchDetails error: \(error.localizedDescription)")
        }
    }

    public struct EmptyResponse: Codable, Sendable {}

    public func addMembers(userIds: [String], currentUserId: String) async -> Bool {
        struct AddBody: Codable {
            let user_ids: [String]
        }

        do {
            let _: EmptyResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversationId)/members",
                method: "POST",
                body: AddBody(user_ids: userIds),
                requiresAuth: true
            )
            await fetchDetails(currentUserId: currentUserId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func removeMember(targetUserId: String, currentUserId: String) async -> Bool {
        do {
            let _: EmptyResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversationId)/members/\(targetUserId)",
                method: "DELETE",
                requiresAuth: true
            )

            // Trigger proactive SenderKey rotation immediately
            MessageCryptoCoordinator.shared.rotateGroupSenderKey(
                conversationId: conversationId,
                senderUserId: currentUserId,
                senderDeviceId: "current"
            )

            await fetchDetails(currentUserId: currentUserId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func updateMemberRole(targetUserId: String, newRole: String, currentUserId: String) async -> Bool {
        struct UpdateRoleBody: Codable {
            let role: String
        }

        do {
            let _: EmptyResponse = try await APIClient.shared.request(
                endpoint: "/conversations/\(conversationId)/members/\(targetUserId)",
                method: "PATCH",
                body: UpdateRoleBody(role: newRole),
                requiresAuth: true
            )
            await fetchDetails(currentUserId: currentUserId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func leaveGroup(currentUserId: String) async -> Bool {
        return await removeMember(targetUserId: currentUserId, currentUserId: currentUserId)
    }

    private func setupRealtime() {
        RealtimeService.shared.onRekeyRequired = { [weak self] convId, evictedId in
            guard let self = self, convId == self.conversationId else { return }
            Task { @MainActor in
                print("[GroupInfoViewModel] Rekey required for group \(convId), evicted user: \(evictedId)")
                MessageCryptoCoordinator.shared.rotateGroupSenderKey(
                    conversationId: convId,
                    senderUserId: evictedId,
                    senderDeviceId: "evicted"
                )
            }
        }

        RealtimeService.shared.onMemberUpdated = { [weak self] convId, userId, newRole in
            guard let self = self, convId == self.conversationId else { return }
            Task { @MainActor in
                if let idx = self.members.firstIndex(where: { $0.id == userId }) {
                    self.members[idx].role = newRole
                }
            }
        }
    }
}
