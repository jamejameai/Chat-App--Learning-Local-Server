import SwiftUI

public struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject public var groupsViewModel: GroupsViewModel
    public let onGroupCreated: (ConversationItem) -> Void

    @State private var groupTitle: String = ""
    @State private var teamMembers: [TeamMember] = []
    @State private var selectedUserIds: Set<String> = []
    @State private var isLoadingTeam: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    public init(
        groupsViewModel: GroupsViewModel,
        onGroupCreated: @escaping (ConversationItem) -> Void = { _ in }
    ) {
        self.groupsViewModel = groupsViewModel
        self.onGroupCreated = onGroupCreated
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Group Info")) {
                    TextField("Group Name", text: $groupTitle)
                        .font(AppTypography.body)
                }

                Section(header: Text("Add Members (\(selectedUserIds.count) selected)")) {
                    if isLoadingTeam {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if teamMembers.isEmpty {
                        Text("No other team members found")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    } else {
                        ForEach(teamMembers) { member in
                            let isSelected = selectedUserIds.contains(member.id)
                            HStack(spacing: AppSpacing.sm) {
                                AvatarView(name: member.title, size: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.title)
                                        .font(AppTypography.body)
                                        .foregroundColor(AppColors.textPrimary)

                                    Text("@\(member.username)")
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.textSecondary)
                                }

                                Spacer()

                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(isSelected ? AppColors.accent : AppColors.textTertiary)
                                    .font(.system(size: 20))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelected {
                                    selectedUserIds.remove(member.id)
                                } else {
                                    selectedUserIds.insert(member.id)
                                }
                            }
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.statusError)
                    }
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action_cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L("action_create")) {
                        submitGroup()
                    }
                    .disabled(groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                    .fontWeight(.semibold)
                }
            }
            .task {
                await fetchTeam()
            }
        }
    }

    private func fetchTeam() async {
        isLoadingTeam = true
        do {
            let members: [TeamMember] = try await APIClient.shared.request(
                endpoint: "/auth/team",
                method: "GET",
                requiresAuth: true
            )
            let currentId = appState.currentUser?.id
            self.teamMembers = members.filter { $0.id != currentId }
            isLoadingTeam = false
        } catch {
            isLoadingTeam = false
            print("[CreateGroupSheet] fetchTeam error: \(error.localizedDescription)")
        }
    }

    private func submitGroup() {
        let title = groupTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            if let group = await groupsViewModel.createGroup(
                title: title,
                memberUserIds: Array(selectedUserIds)
            ) {
                await MainActor.run {
                    self.isSubmitting = false
                    self.onGroupCreated(group)
                    self.dismiss()
                }
            } else {
                await MainActor.run {
                    self.isSubmitting = false
                    self.errorMessage = groupsViewModel.errorMessage ?? "Failed to create group"
                }
            }
        }
    }
}
