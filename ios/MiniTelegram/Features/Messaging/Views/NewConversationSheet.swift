import SwiftUI

public struct NewConversationSheet: View {
    @ObservedObject public var viewModel: ConversationsViewModel
    @Binding public var selectedConversation: ConversationItem?
    /// Shows a "New Group" row at the top when set
    public var onNewGroup: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    @State private var filterQuery: String = ""

    public init(
        viewModel: ConversationsViewModel,
        selectedConversation: Binding<ConversationItem?>,
        onNewGroup: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._selectedConversation = selectedConversation
        self.onNewGroup = onNewGroup
    }

    private var filteredMembers: [TeamMember] {
        if filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return viewModel.teamMembers
        }
        return viewModel.teamMembers.filter {
            $0.title.localizedCaseInsensitiveContains(filterQuery) ||
            $0.username.localizedCaseInsensitiveContains(filterQuery)
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(AppColors.textTertiary)
                    TextField(L("chats_search_placeholder"), text: $filterQuery)
                        .font(AppTypography.body)
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 8)
                .background(AppColors.surface)
                .cornerRadius(AppCornerRadius.md)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)

                if let onNewGroup, filterQuery.isEmpty {
                    Button(action: onNewGroup) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(AppColors.accent))
                            Text("New Group")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppColors.textTertiary)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 72)
                }

                if filteredMembers.isEmpty {
                    EmptyStateView(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "No People Found",
                        description: "Nobody matched your search."
                    )
                } else {
                    List(filteredMembers) { member in
                        Button(action: {
                            Task {
                                if let conv = await viewModel.createDirectConversation(
                                    recipientUserId: member.id,
                                    title: member.title
                                ) {
                                    selectedConversation = conv
                                    dismiss()
                                }
                            }
                        }) {
                            HStack(spacing: AppSpacing.sm) {
                                AvatarView(name: member.title, avatarUrl: member.avatarUrl, size: 44)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.title)
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.textPrimary)

                                    Text("@\(member.username)")
                                        .font(AppTypography.footnote)
                                        .foregroundColor(AppColors.textSecondary)
                                }

                                Spacer()

                                Image(systemName: "bubble.right.fill")
                                    .foregroundColor(AppColors.accent)
                                    .font(.system(size: 16))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action_cancel")) {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.fetchTeamMembers()
            }
        }
    }
}
