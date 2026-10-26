import SwiftUI

public struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ProfileViewModel()
    @ObservedObject private var presence = PresenceManager.shared
    @State private var showingEditProfile = false
    @State private var showingAddFriendAlert = false
    @State private var manualFriendIdentifier = ""
    @State private var activeConversationForChat: ConversationItem? = nil
    @State private var showCallDialogForFriend: FriendDTO? = nil
    @State private var profileFriend: FriendDTO? = nil
    @State private var chatOpenedFromProfile: ConversationItem? = nil

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // My profile: banner + photo, name, @username, bio
                VStack(spacing: AppSpacing.md) {
                    ProfileHeaderView(
                        name: appState.currentUser?.displayName ?? "User",
                        username: appState.currentUser?.username,
                        avatarUrl: appState.currentUser?.avatarUrl,
                        coverUrl: appState.currentUser?.coverUrl,
                        borderTemplate: appState.currentUser?.borderTemplateEnum ?? .platinumExecutive,
                        bio: appState.currentUser?.bio,
                        isOnline: true,
                        isDeveloper: appState.currentUser?.isDeveloper ?? false,
                        isOwner: appState.currentUser?.isAppOwner ?? false,
                        nameColor: appState.currentUser?.nameColor
                    )

                    HStack(spacing: AppSpacing.sm) {
                        ProfileStatView(value: "\(viewModel.friends.count)", label: "Friends")
                        ProfileStatView(value: "\(LocalDatabaseManager.shared.getConversations().count)", label: "Chats")
                    }

                    ProfileActionButton(title: "Edit Profile", systemImage: "pencil", filled: true) {
                        viewModel.prepareEdit(from: appState.currentUser)
                        showingEditProfile = true
                    }

                    if let phone = appState.currentUser?.phoneNumber, !phone.isEmpty {
                        ProfileInfoCard {
                            ProfileInfoRow(systemImage: "phone.fill", title: "Phone", value: phone)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)


                DeveloperProfileSections(
                    profile: appState.currentUser?.developerProfile ?? DeveloperProfile(),
                    showsEmptyState: true
                )
                .padding(.horizontal, AppSpacing.md)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColors.statusError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.md)
                }

                // Search Bar to Discover Friends (Instagram / Facebook Style)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppColors.textTertiary)

                        TextField("Find friends by username, name, or phone...", text: $viewModel.searchQuery)
                            .font(AppTypography.body)
                            .autocapitalization(.none)

                        if !viewModel.searchQuery.isEmpty {
                            Button(action: { viewModel.searchQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 10)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(AppCornerRadius.md)
                    .padding(.horizontal, AppSpacing.md)

                    HStack {
                        Text(viewModel.isSearching ? "Search Results" : "My Friends (\(viewModel.friends.count))")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.textPrimary)

                        Spacer()

                        Button(action: {
                            showingAddFriendAlert = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill.badge.plus")
                                Text("Add Friend")
                            }
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.accent)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.xs)
                }

                // Friends or Search Results Content
                if viewModel.isSearching {
                    if viewModel.searchResults.isEmpty {
                        VStack(spacing: AppSpacing.sm) {
                            Image(systemName: "person.slash")
                                .font(.system(size: 36))
                                .foregroundColor(AppColors.textTertiary)
                            Text("No users found")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xl)
                    } else {
                        LazyVStack(spacing: AppSpacing.xs) {
                            ForEach(viewModel.searchResults) { user in
                                friendCard(friend: user, isSearchResult: true)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }
                } else {
                    if viewModel.friends.isEmpty && !viewModel.isLoading {
                        VStack(spacing: AppSpacing.md) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 42))
                                .foregroundColor(AppColors.textTertiary)

                            Text("No Friends Yet")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.textPrimary)

                            Text("Search above to connect with friends, message like Telegram, and call like Discord!")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, AppSpacing.xl)

                            Button(action: {
                                showingAddFriendAlert = true
                            }) {
                                HStack {
                                    Image(systemName: "person.fill.badge.plus")
                                    Text("Add Friend by Username")
                                }
                                .font(AppTypography.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, 10)
                                .background(AppColors.accent)
                                .cornerRadius(AppCornerRadius.full)
                            }
                            .padding(.top, AppSpacing.xs)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xxl)
                    } else {
                        LazyVStack(spacing: AppSpacing.xs) {
                            ForEach(viewModel.friends) { friend in
                                friendCard(friend: friend, isSearchResult: false)
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.background)
        .navigationTitle("Profile & Friends")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadFriends()
        }
        .task {
            await viewModel.loadCurrentProfile(appState: appState)
            await viewModel.loadFriends()
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileSheet(viewModel: viewModel)
        }
        .alert("Add Friend", isPresented: $showingAddFriendAlert) {
            TextField("Enter username or phone number", text: $manualFriendIdentifier)
                .autocapitalization(.none)
            Button("Add") {
                Task {
                    _ = await viewModel.addFriend(identifier: manualFriendIdentifier)
                    manualFriendIdentifier = ""
                }
            }
            Button("Cancel", role: .cancel) {
                manualFriendIdentifier = ""
            }
        } message: {
            Text("Enter the username or phone number of the person you'd like to connect with.")
        }
        .confirmationDialog(
            "Start Call with \(showCallDialogForFriend?.display_name ?? "")",
            isPresented: Binding(
                get: { showCallDialogForFriend != nil },
                set: { if !$0 { showCallDialogForFriend = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let friend = showCallDialogForFriend {
                Button("Voice Call (Discord style)") {
                    Task {
                        if let conv = await viewModel.getOrCreateConversation(for: friend) {
                            await CallManager.shared.startCall(
                                conversationId: conv.id,
                                title: friend.display_name,
                                callType: .audio
                            )
                        }
                    }
                }

                Button("Video Call") {
                    Task {
                        if let conv = await viewModel.getOrCreateConversation(for: friend) {
                            await CallManager.shared.startCall(
                                conversationId: conv.id,
                                title: friend.display_name,
                                callType: .video
                            )
                        }
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        }
        .navigationDestination(item: $activeConversationForChat) { conv in
            ChatDetailView(conversation: conv)
        }
        .sheet(item: $profileFriend, onDismiss: {
            // Open the chat only after the sheet has gone, then refresh (friend may have been added/removed)
            if let conv = chatOpenedFromProfile {
                chatOpenedFromProfile = nil
                activeConversationForChat = conv
            }
            Task { await viewModel.loadFriends() }
        }) { friend in
            FriendProfileView(
                userId: friend.id,
                name: friend.display_name,
                avatarUrl: friend.avatar_url,
                onMessage: { conv in
                    chatOpenedFromProfile = conv
                    profileFriend = nil
                }
            )
        }
    }

    @ViewBuilder
    private func friendCard(friend: FriendDTO, isSearchResult: Bool) -> some View {
        let isFriendOnline = presence.isOnline(friend.id, fallback: friend.is_online ?? false)
        let statusStr = presence.statusText(for: friend.id, isOnlineFallback: friend.is_online ?? false)

        HStack(spacing: AppSpacing.sm) {
            // Tap the photo or name to view the profile
            Button(action: { profileFriend = friend }) {
                HStack(spacing: AppSpacing.sm) {
                    AvatarView(
                        name: friend.display_name,
                        avatarUrl: friend.avatar_url,
                        size: 52,
                        isOnline: isFriendOnline,
                        borderTemplate: friend.borderTemplateEnum
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        AccountDisplayNameView(
                            name: friend.display_name,
                            isDeveloper: friend.isDeveloper,
                            isOwner: friend.isAppOwner,
                            nameColorHex: friend.name_color,
                            font: AppTypography.headline,
                            color: AppColors.textPrimary,
                            badgeSize: 14
                        )

                        HStack(spacing: 5) {
                            Text("@\(friend.username)")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.textSecondary)

                            if !statusStr.isEmpty {
                                Text("•")
                                    .font(.system(size: 9))
                                    .foregroundColor(AppColors.textTertiary)
                                Text(statusStr)
                                    .font(AppTypography.caption)
                                    .foregroundColor(isFriendOnline ? AppColors.statusOnline : AppColors.textSecondary)
                            }
                        }

                        if let bio = friend.bio, !bio.isEmpty {
                            Text(bio)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if isSearchResult && !(friend.is_friend ?? false) {
                // Add Friend Action
                Button(action: {
                    Task {
                        _ = await viewModel.addFriend(identifier: friend.username)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill.badge.plus")
                        Text("Add")
                    }
                    .font(AppTypography.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 6)
                    .background(AppColors.accent)
                    .cornerRadius(AppCornerRadius.full)
                }
            } else {
                // Active Friend Action Buttons: Message (Telegram) and Call (Discord)
                HStack(spacing: 8) {
                    // Telegram-style Message button
                    Button(action: {
                        Task {
                            if let conv = await viewModel.getOrCreateConversation(for: friend) {
                                activeConversationForChat = conv
                            }
                        }
                    }) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.accent)
                            .frame(width: 36, height: 36)
                            .background(AppColors.accentLight)
                            .clipShape(Circle())
                    }

                    // Discord-style Call button
                    Button(action: {
                        showCallDialogForFriend = friend
                    }) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.statusOnline)
                            .frame(width: 36, height: 36)
                            .background(AppColors.statusOnline.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(AppSpacing.sm)
        .background(AppColors.secondaryBackground)
        .cornerRadius(AppCornerRadius.md)
        .contextMenu {
            if !isSearchResult || (friend.is_friend ?? false) {
                Button(role: .destructive, action: {
                    Task {
                        await viewModel.removeFriend(friendId: friend.id)
                    }
                }) {
                    Label("Remove Friend", systemImage: "person.fill.xmark")
                }
            }
        }
    }
}
