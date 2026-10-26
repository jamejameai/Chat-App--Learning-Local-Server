import SwiftUI

public struct AddGroupMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject public var groupInfoViewModel: GroupInfoViewModel

    @State private var availableMembers: [TeamMember] = []
    @State private var selectedUserIds: Set<String> = []
    @State private var isLoading: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    public init(groupInfoViewModel: GroupInfoViewModel) {
        self.groupInfoViewModel = groupInfoViewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Select Team Members")) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if availableMembers.isEmpty {
                        Text("All team members are already in this group")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)
                    } else {
                        ForEach(availableMembers) { member in
                            let isSelected = selectedUserIds.contains(member.id)
                            HStack(spacing: AppSpacing.sm) {
                                AvatarView(name: member.title, avatarUrl: member.avatarUrl, size: 36)

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
            .navigationTitle("Add Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("action_cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L("action_add")) {
                        submit()
                    }
                    .disabled(selectedUserIds.isEmpty || isSubmitting)
                    .fontWeight(.semibold)
                }
            }
            .task {
                await fetchAvailableMembers()
            }
        }
    }

    private func fetchAvailableMembers() async {
        isLoading = true
        do {
            let team: [TeamMember] = try await APIClient.shared.request(
                endpoint: "/auth/team",
                method: "GET",
                requiresAuth: true
            )
            let existingMemberIds = Set(groupInfoViewModel.members.map { $0.id })
            self.availableMembers = team.filter { !existingMemberIds.contains($0.id) }
            isLoading = false
        } catch {
            isLoading = false
            print("[AddGroupMemberSheet] fetchAvailableMembers error: \(error.localizedDescription)")
        }
    }

    private func submit() {
        guard let currentUserId = appState.currentUser?.id else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            let success = await groupInfoViewModel.addMembers(
                userIds: Array(selectedUserIds),
                currentUserId: currentUserId
            )
            await MainActor.run {
                self.isSubmitting = false
                if success {
                    self.dismiss()
                } else {
                    self.errorMessage = groupInfoViewModel.errorMessage ?? "Failed to add members"
                }
            }
        }
    }
}
