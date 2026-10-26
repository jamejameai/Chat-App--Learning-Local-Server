import Foundation
import SwiftUI
import Combine

/// Loads another user's public profile and handles the actions on it.
@MainActor
public final class FriendProfileViewModel: ObservableObject {
    @Published public private(set) var profile: UserPublicProfileDTO?
    @Published public var isLoading: Bool = false
    @Published public var isWorking: Bool = false
    @Published public var errorMessage: String?

    public let userId: String

    public init(userId: String) {
        self.userId = userId
    }

    public func load() async {
        isLoading = profile == nil
        errorMessage = nil
        do {
            profile = try await APIClient.shared.request(endpoint: "/friends/profile/\(userId)")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    public func addFriend() async {
        isWorking = true
        errorMessage = nil
        do {
            let _: AddFriendResponse = try await APIClient.shared.request(
                endpoint: "/friends/add",
                method: "POST",
                body: AddFriendPayload(identifier: userId)
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    public func removeFriend() async {
        isWorking = true
        errorMessage = nil
        do {
            struct RemoveResponse: Codable {}
            let _: RemoveResponse = try await APIClient.shared.request(
                endpoint: "/friends/\(userId)",
                method: "DELETE"
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    /// The 1:1 chat with this user, created on the server if it doesn't exist yet.
    public func conversation() async -> ConversationItem? {
        guard let profile else { return nil }

        if let conversationId = profile.conversation_id, !conversationId.isEmpty {
            return ConversationItem(
                id: conversationId,
                type: "direct",
                title: profile.display_name,
                avatarUrl: profile.avatar_url,
                recipientUserId: profile.id
            )
        }

        isWorking = true
        defer { isWorking = false }
        do {
            struct CreateConversationBody: Codable {
                let type: String
                let participant_user_ids: [String]
                let title: String?
            }
            struct CreatedConversation: Codable {
                let id: String
            }
            let created: CreatedConversation = try await APIClient.shared.request(
                endpoint: "/conversations",
                method: "POST",
                body: CreateConversationBody(type: "direct", participant_user_ids: [profile.id], title: profile.display_name)
            )
            return ConversationItem(
                id: created.id,
                type: "direct",
                title: profile.display_name,
                avatarUrl: profile.avatar_url,
                recipientUserId: profile.id
            )
        } catch {
            errorMessage = "Couldn't open the chat: \(error.localizedDescription)"
            return nil
        }
    }
}
