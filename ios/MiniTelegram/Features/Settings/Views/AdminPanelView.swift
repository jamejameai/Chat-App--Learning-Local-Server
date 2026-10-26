import SwiftUI

/// Owner and Administrator Control Center.
/// Allows jame.kh (App Owner) and super-admins to inspect real-time system metrics,
/// control user account statuses, modify roles, revoke active sessions, and send broadcasts.
/// Built with a modern, clean, and luxury obsidian design system. Strictly zero emojis.
public struct AdminPanelView: View {
    @StateObject private var viewModel = AdminViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedUserForActions: AdminUserDTO?
    @State private var showingStatusConfirm = false
    @State private var showingRoleSheet = false
    @State private var showingRevokeConfirm = false
    @State private var showingDeleteConfirm = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                // System Metrics Overview
                systemMetricsSection

                // Broadcast & Fast Controls
                broadcastSection

                // User Management Section
                userManagementSection
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.background)
        .navigationTitle("Owner Control Center")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    Task { await viewModel.loadData() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .task {
            await viewModel.loadData()
        }
        .sheet(isPresented: $viewModel.showingBroadcastSheet) {
            broadcastComposerSheet
        }
        .confirmationDialog(
            "Account Actions for @\(selectedUserForActions?.username ?? "")",
            isPresented: Binding(
                get: { selectedUserForActions != nil && !showingDeleteConfirm && !showingRevokeConfirm && !showingRoleSheet },
                set: { if !$0 { selectedUserForActions = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let user = selectedUserForActions {
                if user.isSuspended {
                    Button("Reinstate Account (Activate)") {
                        Task { await viewModel.updateUserStatus(userId: user.id, newStatus: "active") }
                    }
                } else {
                    Button("Suspend Account", role: .destructive) {
                        Task { await viewModel.updateUserStatus(userId: user.id, newStatus: "suspended") }
                    }
                }

                Button("Modify Role...") {
                    showingRoleSheet = true
                }

                Button("Revoke All Active Sessions") {
                    showingRevokeConfirm = true
                }

                if !user.isOwner {
                    Button("Permanently Delete User", role: .destructive) {
                        showingDeleteConfirm = true
                    }
                }

                Button("Cancel", role: .cancel) {
                    selectedUserForActions = nil
                }
            }
        }
        .confirmationDialog(
            "Revoke all sessions for @\(selectedUserForActions?.username ?? "")?",
            isPresented: $showingRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button("Revoke All Devices", role: .destructive) {
                if let user = selectedUserForActions {
                    Task { await viewModel.revokeUserSessions(userId: user.id) }
                }
            }
            Button("Cancel", role: .cancel) {
                selectedUserForActions = nil
            }
        }
        .confirmationDialog(
            "Delete user @\(selectedUserForActions?.username ?? "") permanently?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                if let user = selectedUserForActions {
                    Task { await viewModel.deleteUser(userId: user.id) }
                }
            }
            Button("Cancel", role: .cancel) {
                selectedUserForActions = nil
            }
        }
        .confirmationDialog(
            "Assign Role for @\(selectedUserForActions?.username ?? "")",
            isPresented: $showingRoleSheet,
            titleVisibility: .visible
        ) {
            Button("App Owner") {
                if let user = selectedUserForActions {
                    Task { await viewModel.updateUserRole(userId: user.id, newRole: "owner") }
                }
            }
            Button("Super-Admin") {
                if let user = selectedUserForActions {
                    Task { await viewModel.updateUserRole(userId: user.id, newRole: "superadmin") }
                }
            }
            Button("Standard Member") {
                if let user = selectedUserForActions {
                    Task { await viewModel.updateUserRole(userId: user.id, newRole: "member") }
                }
            }
            Button("Cancel", role: .cancel) {
                selectedUserForActions = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let feedback = viewModel.actionFeedbackMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(Color(red: 0.83, green: 0.69, blue: 0.35))
                    Text(feedback)
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - System Metrics Section

    private var systemMetricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SYSTEM TELEMETRY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
                    .tracking(1.0)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.22, green: 0.78, blue: 0.45))
                        .frame(width: 7, height: 7)
                    Text("ACTIVE SFU & MONOLITH")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(red: 0.22, green: 0.78, blue: 0.45))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(red: 0.22, green: 0.78, blue: 0.45).opacity(0.12), in: Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricCard(
                    title: "Total Users",
                    value: "\(viewModel.stats?.total_users ?? viewModel.users.count)",
                    icon: "person.2.fill",
                    accent: Color(red: 0.83, green: 0.69, blue: 0.35)
                )

                metricCard(
                    title: "Active Now",
                    value: "\(viewModel.stats?.active_users ?? max(1, viewModel.users.filter { !$0.isSuspended }.count))",
                    icon: "antenna.radiowaves.left.and.right",
                    accent: Color(red: 0.38, green: 0.76, blue: 0.98)
                )

                metricCard(
                    title: "Conversations",
                    value: "\(viewModel.stats?.total_conversations ?? 0)",
                    icon: "bubble.left.and.bubble.right.fill",
                    accent: Color(red: 0.65, green: 0.58, blue: 0.92)
                )

                metricCard(
                    title: "Audio & Video Calls",
                    value: "\(viewModel.stats?.total_calls ?? 0)",
                    icon: "phone.badge.checkmark",
                    accent: Color(red: 0.85, green: 0.82, blue: 0.75)
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func metricCard(title: String, value: String, icon: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accent)
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.75)
                )
        )
    }

    // MARK: - Broadcast Section

    private var broadcastSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("App Announcement")
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textPrimary)
                Text("Push instant alert to all active sessions")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button(action: {
                viewModel.showingBroadcastSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Broadcast")
                        .font(AppTypography.subheadline.weight(.semibold))
                }
                .foregroundColor(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.90, blue: 0.72),
                            Color(red: 0.83, green: 0.69, blue: 0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule()
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - User Management Section

    private var userManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("USER ACCOUNTS DIRECTORY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
                    .tracking(1.0)

                Spacer()

                Text("\(viewModel.filteredUsers.count) accounts")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
            }

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textTertiary)

                TextField("Search by name, username or phone...", text: $viewModel.searchQuery)
                    .font(AppTypography.subheadline)
                    .foregroundColor(AppColors.textPrimary)

                if !viewModel.searchQuery.isEmpty {
                    Button(action: { viewModel.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 0.75)
                    )
            )

            // Role Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    roleFilterChip(title: "All Users", key: "all")
                    roleFilterChip(title: "Owner", key: "owner")
                    roleFilterChip(title: "Super-Admin", key: "superadmin")
                    roleFilterChip(title: "Members", key: "member")
                }
            }

            // User List
            if viewModel.isLoading && viewModel.users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if viewModel.filteredUsers.isEmpty {
                EmptyStateView(
                    icon: "person.slash",
                    title: "No Users Found",
                    description: "No accounts match the specified criteria."
                )
                .padding(.vertical, 30)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.filteredUsers) { user in
                        adminUserRow(user)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.10, green: 0.11, blue: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func roleFilterChip(title: String, key: String) -> some View {
        let isSelected = viewModel.selectedRoleFilter == key
        return Button(action: {
            viewModel.selectedRoleFilter = key
        }) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? Color.white : AppColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.04))
                        .overlay(
                            Capsule().stroke(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 0.75)
                        )
                )
        }
    }

    private func adminUserRow(_ user: AdminUserDTO) -> some View {
        let border = ProfileBorderTemplate.from(raw: user.border_template)

        return Button(action: {
            selectedUserForActions = user
        }) {
            HStack(spacing: 12) {
                AvatarView(
                    name: user.display_name,
                    avatarUrl: user.avatar_url,
                    size: 42,
                    borderTemplate: border
                )

                VStack(alignment: .leading, spacing: 3) {
                    AccountDisplayNameView(
                        name: user.display_name,
                        isDeveloper: user.isOwner,
                        isOwner: user.isOwner,
                        nameColorHex: user.name_color,
                        font: AppTypography.body.weight(.semibold),
                        color: AppColors.textPrimary,
                        badgeSize: 14
                    )

                    HStack(spacing: 6) {
                        Text("@\(user.username)")
                            .font(AppTypography.caption)
                            .foregroundColor(AppColors.textSecondary)

                        if let phone = user.phone_number, !phone.isEmpty {
                            Text("•")
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textTertiary)
                            Text(phone)
                                .font(AppTypography.caption)
                                .foregroundColor(AppColors.textTertiary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    // Role Badge
                    roleBadge(for: user.role)

                    // Status Badge
                    if user.isSuspended {
                        Text("SUSPENDED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.95, green: 0.32, blue: 0.38))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.95, green: 0.32, blue: 0.38).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    } else {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.22, green: 0.78, blue: 0.45))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.22, green: 0.78, blue: 0.45).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
                }

                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textTertiary)
                    .frame(width: 24, height: 24)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.04), lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func roleBadge(for role: String) -> some View {
        switch role.lowercased() {
        case "owner":
            return AnyView(
                Text("OWNER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.96, green: 0.90, blue: 0.72))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.60, green: 0.44, blue: 0.18).opacity(0.4), Color(red: 0.30, green: 0.22, blue: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            )
        case "superadmin":
            return AnyView(
                Text("ADMIN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.88, green: 0.90, blue: 0.95))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            )
        default:
            return AnyView(
                Text("MEMBER")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(AppColors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
            )
        }
    }

    // MARK: - Broadcast Composer Sheet

    private var broadcastComposerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TITLE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)

                    TextField("Announcement Subject", text: $viewModel.broadcastTitle)
                        .padding(12)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(AppColors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("MESSAGE BODY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(AppColors.textTertiary)

                    TextEditor(text: $viewModel.broadcastMessage)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundColor(AppColors.textPrimary)
                }

                Spacer()

                Button(action: {
                    Task { await viewModel.sendBroadcast() }
                }) {
                    HStack(spacing: 8) {
                        if viewModel.isBroadcasting {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Send to All Users")
                        }
                    }
                    .font(AppTypography.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.90, blue: 0.72),
                                Color(red: 0.83, green: 0.69, blue: 0.35)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
                .disabled(viewModel.broadcastTitle.isEmpty || viewModel.broadcastMessage.isEmpty || viewModel.isBroadcasting)
            }
            .padding(16)
            .background(AppColors.background)
            .navigationTitle("New Broadcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.showingBroadcastSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
