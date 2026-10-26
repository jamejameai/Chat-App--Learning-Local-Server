import Foundation
import SwiftUI
import Combine

@MainActor
public final class ProfileViewModel: ObservableObject {
    @Published public var friends: [FriendDTO] = []
    @Published public var searchResults: [FriendDTO] = []
    @Published public var searchQuery: String = ""
    @Published public var isSearching: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var isUpdatingProfile: Bool = false
    @Published public var errorMessage: String?
    @Published public var successMessage: String?

    // Profile Edit State
    @Published public var editDisplayName: String = ""
    @Published public var editUsername: String = ""
    @Published public var editPhoneNumber: String = ""
    @Published public var editBio: String = ""
    @Published public var editAvatarBase64: String? = nil
    @Published public var editCoverUrl: String = "cover:obsidian"
    @Published public var editBorderTemplate: String = "platinumExecutive"
    @Published public var editNameColor: String = ""
    @Published public var editDeveloperHeadline = ""
    @Published public var editSkills = ""
    @Published public var editWebsiteURL = ""
    @Published public var editGitHubURL = ""
    @Published public var editLinkedInURL = ""
    @Published public var editInstagramURL = ""
    @Published public var editXURL = ""
    @Published public var editCurrentlyBuilding = ""
    @Published public var editWorkAvailability = "not_available"
    @Published public var editLocation = ""
    @Published public var editProjects: [DeveloperProject] = []


    private var cancellables = Set<AnyCancellable>()

    public init() {
        setupSearchDebounce()
    }

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.searchResults = []
                    self.isSearching = false
                } else {
                    self.isSearching = true
                    Task {
                        await self.searchUsers(query: trimmed)
                    }
                }
            }
            .store(in: &cancellables)
    }

    public func loadFriends() async {
        isLoading = true
        errorMessage = nil

        do {
            let res: [FriendDTO] = try await APIClient.shared.request(
                endpoint: "/friends",
                method: "GET"
            )
            self.friends = res
            self.isLoading = false
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }

    public func loadCurrentProfile(appState: AppState) async {
        guard let device = appState.currentDevice else { return }
        do {
            let user: UserDTO = try await APIClient.shared.request(endpoint: "/auth/me")
            appState.setAuthenticated(
                user: UserProfile(from: user),
                device: device
            )
        } catch {
            errorMessage = "Couldn't refresh your profile: \(error.localizedDescription)"
        }
    }


    public func searchUsers(query: String) async {
        guard !query.isEmpty else { return }
        do {
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
            let res: [FriendDTO] = try await APIClient.shared.request(
                endpoint: "/friends/search?q=\(encoded)",
                method: "GET"
            )
            self.searchResults = res
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func addFriend(identifier: String) async -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        isLoading = true
        errorMessage = nil
        do {
            let payload = AddFriendPayload(identifier: trimmed)
            let res: AddFriendResponse = try await APIClient.shared.request(
                endpoint: "/friends/add",
                method: "POST",
                body: payload
            )
            self.successMessage = "Added \(res.friend.display_name) as friend!"
            LuxuryAlertManager.shared.showFriendAlert(
                name: res.friend.display_name,
                username: res.friend.username,
                avatarUrl: res.friend.avatar_url,
                borderTemplate: ProfileBorderTemplate.from(raw: res.friend.border_template),
                isSender: true
            )
            await loadFriends()
            NotificationCenter.default.post(name: .friendsChanged, object: nil)
            // If in search mode, refresh search
            if !searchQuery.isEmpty {
                await searchUsers(query: searchQuery)
            }
            isLoading = false
            return true

        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func removeFriend(friendId: String) async {
        errorMessage = nil
        do {
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await APIClient.shared.request(
                endpoint: "/friends/\(friendId)",
                method: "DELETE"
            )
            self.friends.removeAll { $0.id == friendId }
            NotificationCenter.default.post(name: .friendsChanged, object: nil)
            if !searchQuery.isEmpty {
                await searchUsers(query: searchQuery)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func prepareEdit(from user: UserProfile?) {
        guard let user = user else { return }
        self.editDisplayName = user.displayName
        self.editUsername = user.username
        self.editPhoneNumber = user.phoneNumber ?? ""
        self.editBio = user.bio ?? ""
        self.editAvatarBase64 = user.avatarUrl
        self.editCoverUrl = user.coverUrl ?? "cover:obsidian"
        self.editBorderTemplate = user.borderTemplate ?? "platinumExecutive"
        self.editNameColor = user.nameColor ?? (user.isAppOwner ? NameColorTheme.imperialRed.hex : "")
        let developerProfile = user.developerProfile ?? DeveloperProfile()
        self.editDeveloperHeadline = developerProfile.headline ?? ""
        self.editSkills = developerProfile.skills.joined(separator: ", ")
        self.editWebsiteURL = developerProfile.websiteURL ?? ""
        self.editGitHubURL = developerProfile.githubURL ?? ""
        self.editLinkedInURL = developerProfile.socialLinks.linkedinURL ?? ""
        self.editInstagramURL = developerProfile.socialLinks.instagramURL ?? ""
        self.editXURL = developerProfile.socialLinks.xURL ?? ""
        self.editCurrentlyBuilding = developerProfile.currentlyBuilding ?? ""
        self.editWorkAvailability = developerProfile.workAvailability ?? "not_listed"
        self.editLocation = developerProfile.location ?? ""
        self.editProjects = developerProfile.projects
    }

    public func saveProfile(appState: AppState) async -> Bool {
        let cleanName = editDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = editUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPhone = editPhoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBio = editBio.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSkills = editSkills
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanProjects = editProjects.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let developerProfile = DeveloperProfile(
            headline: optionalValue(editDeveloperHeadline),
            skills: cleanSkills,
            projects: cleanProjects,
            websiteURL: optionalValue(editWebsiteURL),
            githubURL: optionalValue(editGitHubURL),
            socialLinks: DeveloperSocialLinks(
                linkedinURL: optionalValue(editLinkedInURL),
                instagramURL: optionalValue(editInstagramURL),
                xURL: optionalValue(editXURL)
            ),
            currentlyBuilding: optionalValue(editCurrentlyBuilding),
            workAvailability: editWorkAvailability == "not_listed" ? nil : editWorkAvailability,
            location: optionalValue(editLocation)
        )

        guard !cleanName.isEmpty else {
            errorMessage = "Display name cannot be empty"
            return false
        }

        isUpdatingProfile = true
        errorMessage = nil

        do {
            let payload = UpdateProfilePayload(
                display_name: cleanName,
                username: cleanUsername.isEmpty ? nil : cleanUsername,
                phone_number: cleanPhone.isEmpty ? nil : cleanPhone,
                avatar_url: editAvatarBase64,
                bio: cleanBio.isEmpty ? nil : cleanBio,
                cover_url: editCoverUrl.isEmpty ? nil : editCoverUrl,
                border_template: editBorderTemplate.isEmpty ? nil : editBorderTemplate,
                name_color: editNameColor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editNameColor.trimmingCharacters(in: .whitespacesAndNewlines),
                developer_profile: developerProfile
            )

            let updatedUser: UserDTO = try await APIClient.shared.request(
                endpoint: "/auth/profile",
                method: "PATCH",
                body: payload
            )

            let newUser = UserProfile(from: updatedUser)

            if let currentDevice = appState.currentDevice {
                appState.setAuthenticated(user: newUser, device: currentDevice)
            }

            isUpdatingProfile = false
            successMessage = "Profile updated successfully!"
            return true
        } catch {
            isUpdatingProfile = false
            errorMessage = error.localizedDescription
            return false
        }
    }


    private func optionalValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func getOrCreateConversation(for friend: FriendDTO) async -> ConversationItem? {
        // If friend already has conversation_id
        if let convId = friend.conversation_id, !convId.isEmpty {
            return ConversationItem(
                id: convId,
                type: "direct",
                title: friend.display_name,
                isOnline: PresenceManager.shared.isOnline(friend.id, fallback: friend.is_online ?? false),
                recipientUserId: friend.id
            )
        }

        // Otherwise request conversation creation
        do {
            struct CreateConvReq: Codable {
                let type: String
                let participant_user_ids: [String]
                let title: String?
            }
            struct ConvResponse: Codable {
                let id: String
                let title: String?
                let type: String?
            }

            let payload = CreateConvReq(
                type: "direct",
                participant_user_ids: [friend.id],
                title: friend.display_name
            )

            let res: ConvResponse = try await APIClient.shared.request(
                endpoint: "/conversations",
                method: "POST",
                body: payload
            )

            return ConversationItem(
                id: res.id,
                type: res.type ?? "direct",
                title: res.title ?? friend.display_name,
                isOnline: PresenceManager.shared.isOnline(friend.id, fallback: friend.is_online ?? false),
                recipientUserId: friend.id
            )
        } catch {
            errorMessage = "Failed to start conversation: \(error.localizedDescription)"
            return nil
        }
    }
}
