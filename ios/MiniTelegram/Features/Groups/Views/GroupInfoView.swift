import SwiftUI

public struct GroupInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: GroupInfoViewModel

    @State private var isShowingAddMember: Bool = false
    @State private var isShowingLeaveAlert: Bool = false
    @State private var selectedMemberToManage: GroupMember? = nil

    public init(conversation: ConversationItem) {
        _viewModel = StateObject(wrappedValue: GroupInfoViewModel(conversation: conversation))
    }

    public var body: some View {
        List {
            // Group Header Section
            Section {
                VStack(spacing: AppSpacing.sm) {
                    AvatarView(name: viewModel.conversationTitle, size: 72)

                    Text(viewModel.conversationTitle)
                        .font(AppTypography.title2)
                        .foregroundColor(AppColors.textPrimary)

                    Text("\(viewModel.members.count) members")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)

                    // E2EE Badge
                    HStack(spacing: 6) {
                        Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.statusOnline)

                        Text("Sender Keys E2EE Protected")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColors.surface)
                    .cornerRadius(AppCornerRadius.full)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
                .listRowBackground(Color.clear)
            }

            // Add Members Action (if Admin/Owner)
            if viewModel.isAdmin {
                Section {
                    Button(action: { isShowingAddMember = true }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "person.badge.plus")
                                .foregroundColor(AppColors.accent)
                                .font(.system(size: 18))

                            Text("Add Members")
                                .font(AppTypography.body)
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
            }

            // Members List Section
            Section(header: Text("Members (\(viewModel.members.count))")) {
                if viewModel.isLoading && viewModel.members.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(viewModel.members) { member in
                        memberRow(member: member)
                    }
                }
            }

            // Leave Group Section
            Section {
                Button(role: .destructive, action: { isShowingLeaveAlert = true }) {
                    HStack {
                        Spacer()
                        Text("Leave Group")
                            .font(AppTypography.body.weight(.semibold))
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Group Info")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingAddMember) {
            AddGroupMemberSheet(groupInfoViewModel: viewModel)
        }
        .alert("Leave Group", isPresented: $isShowingLeaveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                leaveGroup()
            }
        } message: {
            Text("Are you sure you want to leave this group? You will no longer receive encrypted messages.")
        }
        .task {
            if let currentUserId = appState.currentUser?.id {
                await viewModel.fetchDetails(currentUserId: currentUserId)
            }
        }
    }

    @ViewBuilder
    private func memberRow(member: GroupMember) -> some View {
        let isCurrentUser = member.id == appState.currentUser?.id

        HStack(spacing: AppSpacing.sm) {
            AvatarView(name: member.title, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(member.title)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textPrimary)

                    if isCurrentUser {
                        Text("(You)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Text("@\(member.username)")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Role Badge
            roleBadge(role: member.role)

            // Management Menu for Owner/Admin
            if canManageMember(member: member) {
                Menu {
                    if viewModel.isOwner {
                        if member.role != "admin" {
                            Button("Make Admin") {
                                updateRole(member: member, role: "admin")
                            }
                        }
                        if member.role != "member" {
                            Button("Set as Member") {
                                updateRole(member: member, role: "member")
                            }
                        }
                        if member.role != "read_only" {
                            Button("Set as Read-Only") {
                                updateRole(member: member, role: "read_only")
                            }
                        }
                    }

                    Button(role: .destructive) {
                        removeMember(member: member)
                    } label: {
                        Label("Remove from Group", systemImage: "person.fill.xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundColor(AppColors.textTertiary)
                        .padding(8)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func roleBadge(role: String) -> some View {
        switch role {
        case "owner":
            Text("Owner")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(AppCornerRadius.sm)
        case "admin":
            Text("Admin")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(AppColors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppColors.accent.opacity(0.15))
                .cornerRadius(AppCornerRadius.sm)
        case "read_only":
            Text("Read-Only")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(AppColors.surface)
                .cornerRadius(AppCornerRadius.sm)
        default:
            EmptyView()
        }
    }

    private func canManageMember(member: GroupMember) -> Bool {
        guard let currentId = appState.currentUser?.id, member.id != currentId else { return false }
        if viewModel.isOwner {
            return true
        }
        if viewModel.isAdmin && member.role != "owner" && member.role != "admin" {
            return true
        }
        return false
    }

    private func updateRole(member: GroupMember, role: String) {
        guard let currentId = appState.currentUser?.id else { return }
        Task {
            _ = await viewModel.updateMemberRole(targetUserId: member.id, newRole: role, currentUserId: currentId)
        }
    }

    private func removeMember(member: GroupMember) {
        guard let currentId = appState.currentUser?.id else { return }
        Task {
            _ = await viewModel.removeMember(targetUserId: member.id, currentUserId: currentId)
        }
    }

    private func leaveGroup() {
        guard let currentId = appState.currentUser?.id else { return }
        Task {
            let success = await viewModel.leaveGroup(currentUserId: currentId)
            if success {
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}
