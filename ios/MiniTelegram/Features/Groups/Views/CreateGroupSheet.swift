import SwiftUI

/// New group: a name plus friends to add. The group opens as soon as it's created.
public struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var groupsViewModel = GroupsViewModel()
    public let onGroupCreated: (ConversationItem) -> Void

    @State private var groupTitle: String = ""
    @State private var friends: [FriendDTO] = []
    @State private var selectedUserIds: Set<String> = []
    @State private var searchText: String = ""
    @State private var isLoadingFriends: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var nameFocused: Bool

    public init(onGroupCreated: @escaping (ConversationItem) -> Void = { _ in }) {
        self.onGroupCreated = onGroupCreated
    }

    private var trimmedTitle: String {
        groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !trimmedTitle.isEmpty && !selectedUserIds.isEmpty && !isSubmitting
    }

    private var filteredFriends: [FriendDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return friends }
        return friends.filter {
            $0.display_name.localizedCaseInsensitiveContains(query) ||
            $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedFriends: [FriendDTO] {
        friends.filter { selectedUserIds.contains($0.id) }
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle().fill(LinearGradient(
                                    colors: [AppColors.accent, AppColors.accentDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            )

                        TextField("Group name", text: $groupTitle)
                            .font(AppTypography.title3)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onChange(of: groupTitle) { _, text in
                                if text.count > 64 { groupTitle = String(text.prefix(64)) }
                            }
                    }
                    .padding(.vertical, 4)
                }

                if !selectedFriends.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.sm) {
                                ForEach(selectedFriends) { friend in
                                    selectedChip(friend)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                }

                Section {
                    if isLoadingFriends && friends.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if friends.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "person.2.slash")
                                .font(.system(size: 28))
                                .foregroundColor(AppColors.textTertiary)
                            Text("Add friends first, then you can put them in a group.")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                    } else {
                        ForEach(filteredFriends) { friend in
                            friendRow(friend)
                        }
                    }
                } header: {
                    Text(selectedUserIds.isEmpty ? "Add Members" : "Add Members · \(selectedUserIds.count) selected")
                }

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.statusError)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search friends")
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action_cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(L("action_create")) {
                            submitGroup()
                        }
                        .disabled(!canCreate)
                        .fontWeight(.semibold)
                    }
                }
            }
            .task {
                await fetchFriends()
                if trimmedTitle.isEmpty { nameFocused = true }
            }
        }
    }

    private func friendRow(_ friend: FriendDTO) -> some View {
        let isSelected = selectedUserIds.contains(friend.id)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if isSelected {
                    selectedUserIds.remove(friend.id)
                } else {
                    selectedUserIds.insert(friend.id)
                }
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                AvatarView(name: friend.display_name, avatarUrl: friend.avatar_url, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ContactNicknames.displayName(userId: friend.id, fallback: friend.display_name))
                        .font(AppTypography.body.weight(.medium))
                        .foregroundColor(AppColors.textPrimary)

                    Text("@\(friend.username)")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? AppColors.accent : AppColors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectedChip(_ friend: FriendDTO) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                _ = selectedUserIds.remove(friend.id)
            }
        } label: {
            VStack(spacing: 4) {
                AvatarView(name: friend.display_name, avatarUrl: friend.avatar_url, size: 44)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white, AppColors.textTertiary)
                            .offset(x: 4, y: -4)
                    }
                Text(friend.display_name.split(separator: " ").first.map(String.init) ?? friend.display_name)
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(friend.display_name)")
    }

    private func fetchFriends() async {
        isLoadingFriends = true
        defer { isLoadingFriends = false }
        do {
            friends = try await APIClient.shared.request(endpoint: "/friends", method: "GET", requiresAuth: true)
        } catch {
            errorMessage = "Couldn't load your friends. Check your connection."
        }
    }

    private func submitGroup() {
        guard canCreate else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            if let group = await groupsViewModel.createGroup(
                title: trimmedTitle,
                memberUserIds: Array(selectedUserIds)
            ) {
                isSubmitting = false
                dismiss()
                onGroupCreated(group)
            } else {
                isSubmitting = false
                errorMessage = groupsViewModel.errorMessage ?? "Couldn't create the group"
            }
        }
    }
}
