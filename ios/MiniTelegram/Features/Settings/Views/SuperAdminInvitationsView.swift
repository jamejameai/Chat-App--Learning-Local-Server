import SwiftUI

@MainActor
public final class SuperAdminInvitationsViewModel: ObservableObject {
    @Published public var invitations: [InvitationItemDTO] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var newlyCreatedCode: String?

    @Published public var selectedRole: String = "member"
    @Published public var selectedDays: Int = 14

    public func fetchInvitations() async {
        isLoading = true
        errorMessage = nil
        do {
            let res: [InvitationItemDTO] = try await APIClient.shared.request(endpoint: "/invitations")
            self.invitations = res
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    public func createInvitation() async {
        isLoading = true
        errorMessage = nil
        do {
            let payload = CreateInvitationPayload(role: selectedRole, expires_in_days: selectedDays)
            let res: InvitationItemDTO = try await APIClient.shared.request(
                endpoint: "/invitations",
                method: "POST",
                body: payload
            )
            self.newlyCreatedCode = res.code
            UIPasteboard.general.string = res.code
            await fetchInvitations()
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    public func revokeInvitation(id: String) async {
        do {
            struct RevokeRes: Codable {
                let success: Bool
            }
            let _: RevokeRes = try await APIClient.shared.request(
                endpoint: "/invitations/\(id)",
                method: "DELETE"
            )
            await fetchInvitations()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

public struct SuperAdminInvitationsView: View {
    @StateObject private var viewModel = SuperAdminInvitationsViewModel()

    public init() {}

    public var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(AppColors.statusError)
                        .font(AppTypography.footnote)
                }
            }

            // Create Invitation Form
            Section(header: Text(L("admin_create_invitation"))) {
                Picker("Role", selection: $viewModel.selectedRole) {
                    Text("Member").tag("member")
                    Text("Super-Admin").tag("superadmin")
                }

                Picker("Validity", selection: $viewModel.selectedDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                }

                PrimaryButton(
                    title: L("admin_create_invitation"),
                    icon: "plus.circle.fill",
                    isLoading: viewModel.isLoading
                ) {
                    Task {
                        await viewModel.createInvitation()
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if let code = viewModel.newlyCreatedCode {
                Section(header: Text("Generated Invitation Code")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(code)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundColor(AppColors.accent)
                            Text("Copied to clipboard")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.statusOnline)
                        }
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = code
                        }) {
                            Image(systemName: "doc.on.doc.fill")
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
            }

            // Active & Past Invitations
            Section(header: Text(L("admin_invitations_title"))) {
                if viewModel.isLoading && viewModel.invitations.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.invitations.isEmpty {
                    Text("No invitations created yet")
                        .foregroundColor(AppColors.textSecondary)
                } else {
                    ForEach(viewModel.invitations) { inv in
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            HStack {
                                Text(inv.code)
                                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                    .foregroundColor(AppColors.textPrimary)

                                Spacer()

                                if inv.revoked {
                                    Text("Revoked")
                                        .font(AppTypography.caption.weight(.bold))
                                        .foregroundColor(AppColors.statusError)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.12))
                                        .cornerRadius(4)
                                } else if inv.used_at != nil {
                                    Text("Used by \(inv.used_by_username ?? "user")")
                                        .font(AppTypography.caption.weight(.bold))
                                        .foregroundColor(AppColors.statusOnline)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(4)
                                } else {
                                    Text("Active (\(inv.role))")
                                        .font(AppTypography.caption.weight(.bold))
                                        .foregroundColor(AppColors.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(AppColors.accentLight)
                                        .cornerRadius(4)
                                }
                            }

                            HStack {
                                Text("Expires: \(inv.expires_at.prefix(10))")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textTertiary)

                                Spacer()

                                if !inv.revoked && inv.used_at == nil {
                                    Button(role: .destructive) {
                                        Task {
                                            await viewModel.revokeInvitation(id: inv.id)
                                        }
                                    } label: {
                                        Text(L("action_delete"))
                                            .font(AppTypography.footnote)
                                            .foregroundColor(AppColors.statusError)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(L("admin_invitations_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.fetchInvitations()
        }
    }
}
