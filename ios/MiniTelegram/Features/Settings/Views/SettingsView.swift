import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = LocalizationManager.shared
    @StateObject private var profileViewModel = ProfileViewModel()

    @State private var isBiometricEnabled: Bool = BiometricAuthManager.shared.isBiometricEnabled
    @State private var identityFingerprint: String = ""
    @State private var serverURL: String = ""
    @State private var showLogoutConfirm: Bool = false
    @State private var logoutErrorMessage: String?
    @State private var showServerConfig: Bool = false
    @State private var showEditProfile: Bool = false

    public init() {}

    public var body: some View {
        List {
            // Profile & Account Customization Section
            Section(header: Text("Account Profile")) {
                Button(action: {
                    profileViewModel.prepareEdit(from: appState.currentUser)
                    showEditProfile = true
                }) {
                    HStack(spacing: AppSpacing.md) {
                        AvatarView(
                            name: appState.currentUser?.displayName ?? "User",
                            avatarUrl: appState.currentUser?.avatarUrl,
                            size: 64,
                            isOnline: true,
                            borderTemplate: appState.currentUser?.borderTemplateEnum ?? .platinumExecutive
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            AccountDisplayNameView(
                                name: appState.currentUser?.displayName ?? "Our Chat User",
                                isDeveloper: appState.currentUser?.isDeveloper ?? false,
                                isOwner: appState.currentUser?.isAppOwner ?? false,
                                nameColorHex: appState.currentUser?.nameColor,
                                font: AppTypography.headline,
                                color: AppColors.textPrimary,
                                badgeSize: 15
                            )

                            Text("@\(appState.currentUser?.username ?? "username")")
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.textSecondary)

                            if let phone = appState.currentUser?.phoneNumber, !phone.isEmpty {
                                Text(phone)
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textTertiary)
                            }

                            if appState.currentUser?.isAppOwner == true {
                                HStack(spacing: AppSpacing.xxs) {
                                    Image(systemName: "crown.fill")
                                    Text("App Owner & Dev")
                                }
                                .font(AppTypography.caption.weight(.semibold))
                                .foregroundColor(Color(red: 0.96, green: 0.90, blue: 0.72))
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.60, green: 0.44, blue: 0.18).opacity(0.4), Color(red: 0.30, green: 0.22, blue: 0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    in: RoundedRectangle(cornerRadius: AppCornerRadius.sm)
                                )
                            } else if appState.currentUser?.isSuperAdmin == true {
                                HStack(spacing: AppSpacing.xxs) {
                                    Image(systemName: "shield.fill")
                                    Text("Super-Admin")
                                }
                                .font(AppTypography.caption.weight(.semibold))
                                .foregroundColor(AppColors.accent)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 2)
                                .background(AppColors.accentLight)
                                .cornerRadius(AppCornerRadius.sm)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.textTertiary)
                    }
                    .padding(.vertical, AppSpacing.xxs)
                }

                Button(action: {
                    profileViewModel.prepareEdit(from: appState.currentUser)
                    showEditProfile = true
                }) {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundColor(AppColors.accent)
                            .frame(width: 24)
                        Text("Customize Profile & Bio")
                            .foregroundColor(AppColors.textPrimary)
                        Spacer()
                    }
                }
            }

            // Security & Privacy
            Section(header: Text(L("settings_section_security"))) {
                Toggle(isOn: $isBiometricEnabled) {
                    HStack {
                        Image(systemName: "faceid")
                            .foregroundColor(AppColors.accent)
                            .frame(width: 24)
                        Text(L("settings_biometric_lock"))
                    }
                }
                .onChange(of: isBiometricEnabled) { newValue in
                    BiometricAuthManager.shared.isBiometricEnabled = newValue
                }

                if !identityFingerprint.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(L("settings_key_fingerprint"))
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        Text(identityFingerprint)
                            .font(.system(.footnote, design: .monospaced).weight(.medium))
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .padding(.vertical, 2)
                }

                NavigationLink(destination: DeviceManagementView()) {
                    HStack {
                        Image(systemName: "iphone.gen3")
                            .foregroundColor(AppColors.accent)
                            .frame(width: 24)
                        Text(L("settings_section_devices"))
                    }
                }
            }

            // App Owner & Super-Admin Control Panel
            if appState.currentUser?.isAppOwner == true || appState.currentUser?.isSuperAdmin == true {
                Section(header: Text("Control Center")) {
                    NavigationLink(destination: AdminPanelView()) {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(Color(red: 0.83, green: 0.69, blue: 0.35))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Owner Control Center")
                                    .foregroundColor(AppColors.textPrimary)
                                    .font(AppTypography.body.weight(.medium))
                                Text("Manage users, status, roles, & broadcast")
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }

                    NavigationLink(destination: SuperAdminInvitationsView()) {
                        HStack {
                            Image(systemName: "envelope.badge.shield.half.filled")
                                .foregroundColor(AppColors.accent)
                                .frame(width: 24)
                            Text(L("admin_invitations_title"))
                        }
                    }
                }
            }

            // Preferences
            Section(header: Text(L("settings_section_preferences"))) {
                NavigationLink(destination: BackgroundNotificationsView()) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(AppColors.accent)
                            .frame(width: 24)
                        Text(L("bark_settings_row"))
                    }
                }

                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(AppColors.accent)
                        .frame(width: 24)
                    Text(L("settings_language"))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { localization.currentLanguage },
                        set: { localization.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(AppColors.accent)
                        .frame(width: 24)
                    Text("Server Endpoint")
                    Spacer()
                    Button(action: { showServerConfig = true }) {
                        Text(serverURL.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "/api/v1", with: ""))
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }

            // Version & Logout
            Section {
                HStack {
                    Text("Our Chat")
                    Spacer()
                    Text(L("settings_app_version", "1.0.0", "1"))
                        .foregroundColor(AppColors.textTertiary)
                }

                Button(role: .destructive, action: {
                    showLogoutConfirm = true
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text(L("settings_logout"))
                    }
                }
            }
        }
        .navigationTitle(L("settings_title"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            self.identityFingerprint = (try? KeychainManager.shared.getString(key: "identity_fingerprint")) ?? ""
            self.serverURL = APIClient.shared.currentBaseURL
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet(viewModel: profileViewModel)
        }
        .confirmationDialog(
            L("settings_logout"),
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button(L("settings_logout"), role: .destructive) {
                Task {
                    let locationStopped = await LiveLocationViewModel.shared.stopForLogout()
                    guard locationStopped else {
                        logoutErrorMessage = LiveLocationViewModel.shared.errorMessage
                            ?? "Your live location could not be cleared. Please try logging out again."
                        return
                    }
                    await BarkRelayManager.shared.disconnectBeforeLogout()
                    RealtimeService.shared.stop()
                    KeychainManager.shared.clearAll()
                    appState.logout()
                }
            }
            Button(L("action_cancel"), role: .cancel) {}
        } message: {
            Text(L("settings_logout_confirm"))
        }
        .alert(
            "Couldn't stop location sharing",
            isPresented: Binding(
                get: { logoutErrorMessage != nil },
                set: { if !$0 { logoutErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { logoutErrorMessage = nil }
        } message: {
            Text(logoutErrorMessage ?? "")
        }
        .alert("Configure Server Base URL", isPresented: $showServerConfig) {
            TextField("e.g. http://100.78.0.52:3001/api/v1", text: $serverURL)
            Button("Save") {
                Task {
                    await APIClient.shared.setBaseURL(serverURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
