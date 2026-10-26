import SwiftUI

/// Another user's profile, opened from the Profile tab, a chat's title, a chat-list long-press or a
/// group's member list.
public struct FriendProfileView: View {
    @StateObject private var viewModel: FriendProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemove = false

    private let fallbackName: String
    private let fallbackAvatarUrl: String?
    /// Shows a "Message" button that hands the chat back to the presenter; nil when already in that chat.
    private let onMessage: ((ConversationItem) -> Void)?

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public init(
        userId: String,
        name: String,
        avatarUrl: String? = nil,
        onMessage: ((ConversationItem) -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: FriendProfileViewModel(userId: userId))
        self.fallbackName = name
        self.fallbackAvatarUrl = avatarUrl
        self.onMessage = onMessage
    }

    @State private var showingNicknameAlert = false
    @State private var nicknameDraft = ""
    @State private var nicknameVersion = 0
    @State private var viewingStory = false
    @ObservedObject private var stories = StoriesStore.shared

    private var realName: String { viewModel.profile?.display_name ?? fallbackName }
    /// Your nickname for them if you set one
    private var displayName: String {
        _ = nicknameVersion
        return ContactNicknames.displayName(userId: viewModel.userId, fallback: realName)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    ProfileHeaderView(
                        name: displayName,
                        username: viewModel.profile?.username,
                        avatarUrl: viewModel.profile?.avatar_url ?? fallbackAvatarUrl,
                        coverUrl: viewModel.profile?.cover_url,
                        borderTemplate: viewModel.profile?.borderTemplateEnum ?? .platinumExecutive,
                        bio: viewModel.profile?.bio,
                        isOnline: viewModel.profile?.is_online ?? false,
                        isDeveloper: viewModel.profile?.isDeveloper ?? false,
                        isOwner: viewModel.profile?.isAppOwner ?? false,
                        nameColor: viewModel.profile?.name_color
                    )

                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.top, AppSpacing.lg)
                    } else if let profile = viewModel.profile {
                        actions(for: profile)
                        DeveloperProfileSections(
                            profile: profile.developer_profile ?? DeveloperProfile()
                        )
                        details(for: profile)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.statusError)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.md)
            }
            .background(AppColors.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.load()
            }
            .fullScreenCover(isPresented: $viewingStory) {
                StoryViewerView(groups: stories.feed, startUserId: viewModel.userId)
            }
            .alert("Nickname", isPresented: $showingNicknameAlert) {
                TextField(realName, text: $nicknameDraft)
                Button("Save") {
                    ContactNicknames.set(nicknameDraft, for: viewModel.userId)
                    nicknameVersion += 1
                }
                if ContactNicknames.nickname(for: viewModel.userId) != nil {
                    Button("Remove Nickname", role: .destructive) {
                        ContactNicknames.set(nil, for: viewModel.userId)
                        nicknameVersion += 1
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Only you see this name.")
            }
            .confirmationDialog(
                "Remove \(displayName) from your friends?",
                isPresented: $confirmingRemove,
                titleVisibility: .visible
            ) {
                Button("Remove Friend", role: .destructive) {
                    Task { await viewModel.removeFriend() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func actions(for profile: UserPublicProfileDTO) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if let onMessage {
                ProfileActionButton(title: "Message", systemImage: "bubble.left.fill", filled: true) {
                    Task {
                        if let conversation = await viewModel.conversation() {
                            onMessage(conversation)
                        }
                    }
                }
            }

            if stories.stories(for: viewModel.userId) != nil {
                ProfileActionButton(title: "Story", systemImage: "circle.dashed.inset.filled") {
                    viewingStory = true
                }
            }

            ProfileActionButton(title: "Nickname", systemImage: "pencil") {
                nicknameDraft = ContactNicknames.nickname(for: viewModel.userId) ?? ""
                showingNicknameAlert = true
            }

            if profile.is_friend {
                ProfileActionButton(title: "Remove", systemImage: "person.fill.xmark", tint: AppColors.statusError) {
                    confirmingRemove = true
                }
            } else {
                ProfileActionButton(title: "Add Friend", systemImage: "person.fill.badge.plus", filled: onMessage == nil) {
                    Task { await viewModel.addFriend() }
                }
            }
        }
        .disabled(viewModel.isWorking)
        .opacity(viewModel.isWorking ? 0.6 : 1)
    }

    @ViewBuilder
    private func details(for profile: UserPublicProfileDTO) -> some View {
        ProfileInfoCard {
            if let phone = profile.phone_number, !phone.isEmpty {
                ProfileInfoRow(systemImage: "phone.fill", title: "Phone", value: phone)
            } else if !profile.is_friend {
                ProfileInfoRow(systemImage: "lock.fill", title: "Phone", value: "Friends only")
            }
            if let since = formattedDate(profile.friends_since) {
                ProfileInfoRow(systemImage: "person.2.fill", title: "Friends since", value: since)
            }
            if let joined = formattedDate(profile.created_at) {
                ProfileInfoRow(systemImage: "calendar", title: "Joined", value: joined)
            }
        }
    }

    private func formattedDate(_ iso: String?) -> String? {
        guard let iso, let date = Self.isoFormatter.date(from: iso) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
