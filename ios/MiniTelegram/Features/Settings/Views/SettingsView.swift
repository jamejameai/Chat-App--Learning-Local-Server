import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = LocalizationManager.shared
    @State private var isBiometricEnabled: Bool = BiometricAuthManager.shared.isBiometricEnabled
    @State private var identityFingerprint: String = ""
    @State private var serverURL: String = ""
    @State private var showLogoutConfirm: Bool = false
    @State private var showServerConfig: Bool = false

    public init() {}

    public var body: some View {
        List {
            // Profile Section
            Section {
                HStack(spacing: AppSpacing.md) {
                    AvatarView(
                        name: appState.currentUser?.displayName ?? "User",
                        size: 60,
                        isOnline: true
                    )

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(appState.currentUser?.displayName ?? "Mini Telegram User")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.textPrimary)

                        Text("@\(appState.currentUser?.username ?? "username")")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textSecondary)

                        if appState.currentUser?.role == "superadmin" {
                            HStack(spacing: AppSpacing.xxs) {
                                Image(systemName: "crown.fill")
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
                }
                .padding(.vertical, AppSpacing.xxs)
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

            // Super-Admin Panel
            if appState.currentUser?.role == "superadmin" {
                Section(header: Text(L("settings_section_admin"))) {
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
                    Text("Mini Telegram")
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
            self.serverURL = UserDefaults.standard.string(forKey: "server_base_url") ?? "http://localhost:3000/api/v1"
        }
        .confirmationDialog(
            L("settings_logout"),
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button(L("settings_logout"), role: .destructive) {
                KeychainManager.shared.clearAll()
                appState.logout()
            }
            Button(L("action_cancel"), role: .cancel) {}
        } message: {
            Text(L("settings_logout_confirm"))
        }
        .alert("Configure Server Base URL", isPresented: $showServerConfig) {
            TextField("e.g. http://192.168.1.150:3000/api/v1", text: $serverURL)
            Button("Save") {
                Task {
                    await APIClient.shared.setBaseURL(serverURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
