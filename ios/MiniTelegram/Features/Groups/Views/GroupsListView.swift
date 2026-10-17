import SwiftUI

public struct GroupsListView: View {
    @StateObject private var viewModel = GroupsViewModel()
    @State private var isShowingCreateGroup: Bool = false
    @State private var selectedGroup: ConversationItem? = nil

    public init() {}

    public var body: some View {
        Group {
            if viewModel.filteredGroups.isEmpty && !viewModel.isLoading {
                emptyGroupsView
            } else {
                List {
                    ForEach(viewModel.filteredGroups) { group in
                        NavigationLink(destination: ChatDetailView(conversation: group)) {
                            GroupRowView(group: group)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(L("groups_title"))
        .searchable(text: $viewModel.searchText, prompt: "Search groups")
        .refreshable {
            await viewModel.syncGroups()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isShowingCreateGroup = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $isShowingCreateGroup) {
            CreateGroupSheet(groupsViewModel: viewModel) { newGroup in
                self.selectedGroup = newGroup
            }
        }
        .task {
            await viewModel.syncGroups()
        }
    }

    private var emptyGroupsView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()

            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 64))
                .foregroundColor(AppColors.accent.opacity(0.8))

            Text("No Groups Yet")
                .font(AppTypography.title2)
                .foregroundColor(AppColors.textPrimary)

            Text("Create encrypted group chats with your team members protected by Signal Sender Keys.")
                .font(AppTypography.body)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            Button(action: { isShowingCreateGroup = true }) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                    Text("Create New Group")
                        .font(AppTypography.headline)
                }
                .foregroundColor(Color.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.accent)
                .cornerRadius(AppCornerRadius.md)
            }
            .padding(.top, AppSpacing.sm)

            Spacer()
        }
        .padding()
    }
}

public struct GroupRowView: View {
    public let group: ConversationItem

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            AvatarView(name: group.title, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(group.title)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 2) {
                        Image(systemName: "person.2")
                            .font(.system(size: 10))
                        Text("\(group.memberCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColors.surface)
                    .cornerRadius(8)

                    Spacer()

                    if let timestamp = group.lastMessageTimestamp {
                        Text(formatTime(timestamp))
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                HStack {
                    Text(group.lastMessageText ?? "No messages yet")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    if group.unreadCount > 0 {
                        Text("\(group.unreadCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.accent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}
