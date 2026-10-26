import SwiftUI

public struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = LocalizationManager.shared
    @StateObject private var viewModel = AuthViewModel()

    @State private var navigateToLogin: Bool = false
    @State private var navigateToRegister: Bool = false
    @State private var showServerAlert: Bool = false
    @State private var serverURLInput: String = APIClient.shared.currentBaseURL
    @State private var testStatus: String? = nil
    @State private var isTesting: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Bar: Server Connection & Language Switcher
                HStack {
                    Button(action: {
                        serverURLInput = APIClient.shared.currentBaseURL
                        testStatus = nil
                        showServerAlert = true
                    }) {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "server.rack")
                            Text("Server")
                        }
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 6)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(AppCornerRadius.full)
                    }

                    Spacer()

                    Menu {
                        ForEach(AppLanguage.allCases) { lang in
                            Button(action: { localization.setLanguage(lang) }) {
                                HStack {
                                    Text(lang.displayName)
                                    if localization.currentLanguage == lang {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "globe")
                            Text(localization.currentLanguage == .khmer ? "ភាសាខ្មែរ" : "English")
                        }
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 6)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(AppCornerRadius.full)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)

                Spacer()

                // Centered Hero Emblem & Brand
                VStack(spacing: AppSpacing.lg) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 112, height: 112)
                        .cornerRadius(28)
                        .shadow(color: AppColors.accent.opacity(0.25), radius: 20, x: 0, y: 10)

                    VStack(spacing: AppSpacing.xs) {
                        Text("Our Chat")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(AppColors.textPrimary)

                        Text("Private social messaging, friend connections, and crystal-clear voice & video calls.")
                            .font(AppTypography.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xl)
                    }
                }

                Spacer()

                // Action Buttons
                VStack(spacing: AppSpacing.sm) {
                    Button(action: {
                        navigateToLogin = true
                    }) {
                        HStack {
                            Text("Log In")
                                .font(AppTypography.headline)
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColors.accent)
                        .cornerRadius(AppCornerRadius.md)
                    }

                    Button(action: {
                        navigateToRegister = true
                    }) {
                        Text("Create Account")
                            .font(AppTypography.headline)
                            .foregroundColor(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(AppCornerRadius.md)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppCornerRadius.md)
                                    .stroke(AppColors.border, lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
            }
            .background(AppColors.background)
            .navigationDestination(isPresented: $navigateToLogin) {
                LoginView(viewModel: viewModel)
            }
            .navigationDestination(isPresented: $navigateToRegister) {
                RegisterView(viewModel: viewModel)
            }
            .sheet(isPresented: $showServerAlert) {
                NavigationStack {
                    Form {
                        Section("Current Server URL") {
                            TextField("https://...", text: $serverURLInput)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)
                        }

                        Section("Network Presets") {
                            Button(action: {
                                serverURLInput = GeneratedNetworkConfig.defaultURL
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Home Server (Tailscale)")
                                            .font(AppTypography.footnote.weight(.semibold))
                                            .foregroundColor(AppColors.textPrimary)
                                        Text(GeneratedNetworkConfig.defaultURL)
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                    Spacer()
                                    if serverURLInput == GeneratedNetworkConfig.defaultURL {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppColors.accent)
                                    }
                                }
                            }

                            if !GeneratedNetworkConfig.localBonjourURL.isEmpty {
                                Button(action: {
                                    serverURLInput = GeneratedNetworkConfig.localBonjourURL
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Local Bonjour Name (mDNS)")
                                                .font(AppTypography.footnote.weight(.semibold))
                                                .foregroundColor(AppColors.textPrimary)
                                            Text(GeneratedNetworkConfig.localBonjourURL)
                                                .font(AppTypography.caption)
                                                .foregroundColor(AppColors.textSecondary)
                                        }
                                        Spacer()
                                        if serverURLInput == GeneratedNetworkConfig.localBonjourURL {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(AppColors.accent)
                                        }
                                    }
                                }
                            }

                            Button(action: {
                                serverURLInput = GeneratedNetworkConfig.cloudflareURL
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Cloudflare HTTPS (Any Network)")
                                            .font(AppTypography.footnote.weight(.semibold))
                                            .foregroundColor(AppColors.textPrimary)
                                        Text("Works on 4G/5G data & isolated Wi-Fi")
                                            .font(AppTypography.caption)
                                            .foregroundColor(AppColors.textSecondary)
                                    }
                                    Spacer()
                                    if serverURLInput.contains("trycloudflare.com") {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppColors.accent)
                                    }
                                }
                            }
                        }

                        Section {
                            Button(action: {
                                isTesting = true
                                testStatus = nil
                                Task {
                                    await APIClient.shared.setBaseURL(serverURLInput)
                                    do {
                                        struct HealthRes: Codable { let status: String }
                                        let _: HealthRes = try await APIClient.shared.request(endpoint: "/health", requiresAuth: false)
                                        await MainActor.run {
                                            testStatus = "Connected successfully! (Server OK)"
                                            isTesting = false
                                        }
                                    } catch {
                                        await MainActor.run {
                                            testStatus = "Connection failed: \(error.localizedDescription)"
                                            isTesting = false
                                        }
                                    }
                                }
                            }) {
                                HStack {
                                    if isTesting {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "bolt.horizontal.fill")
                                    }
                                    Text("Test Connection")
                                }
                            }
                            .disabled(isTesting)

                            if let testStatus = testStatus {
                                Text(testStatus)
                                    .font(AppTypography.caption)
                                    .foregroundColor(testStatus.contains("successfully") ? AppColors.statusOnline : AppColors.statusError)
                            }
                        }
                    }
                    .navigationTitle("Server Connection")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                Task {
                                    await APIClient.shared.setBaseURL(serverURLInput)
                                }
                                showServerAlert = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func featureHighlightRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .cornerRadius(AppCornerRadius.sm)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.footnote.weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
        }
    }
}
