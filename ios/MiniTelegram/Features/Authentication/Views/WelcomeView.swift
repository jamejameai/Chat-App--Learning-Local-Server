import SwiftUI

public struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var localization = LocalizationManager.shared
    @StateObject private var viewModel = AuthViewModel()

    @State private var isLoginMode: Bool = false
    @State private var navigateToSetup: Bool = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top language switch button
                HStack {
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
                        .padding(.vertical, AppSpacing.xxs)
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(AppCornerRadius.full)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)

                Spacer()

                // Brand Emblem & Title
                VStack(spacing: AppSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accentLight)
                            .frame(width: 88, height: 88)

                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(AppColors.accent)
                            .offset(x: -2, y: 2)
                    }

                    Text(L("auth_welcome_title"))
                        .font(AppTypography.largeTitle)
                        .foregroundColor(AppColors.textPrimary)

                    Text(L("auth_welcome_subtitle"))
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                Spacer()

                // Form Section
                VStack(spacing: AppSpacing.md) {
                    if let errorMessage = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(AppColors.statusError)
                            Text(errorMessage)
                                .font(AppTypography.footnote)
                                .foregroundColor(AppColors.statusError)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isLoginMode {
                        CustomTextField(
                            placeholder: L("auth_username_placeholder"),
                            text: $viewModel.username,
                            autocapitalization: .never
                        )

                        CustomTextField(
                            placeholder: L("auth_password_placeholder"),
                            text: $viewModel.password,
                            isSecure: true
                        )

                        PrimaryButton(
                            title: L("auth_login_button"),
                            icon: "arrow.right",
                            isLoading: viewModel.isLoading
                        ) {
                            Task {
                                _ = await viewModel.login(appState: appState)
                            }
                        }

                        Button(action: {
                            isLoginMode = false
                            viewModel.errorMessage = nil
                        }) {
                            Text(L("auth_need_account"))
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.accent)
                        }
                        .padding(.top, AppSpacing.xs)

                    } else {
                        CustomTextField(
                            placeholder: L("auth_invite_code_placeholder"),
                            text: $viewModel.inviteCode,
                            autocapitalization: .never
                        )

                        PrimaryButton(
                            title: L("auth_verify_invite_button"),
                            icon: "checkmark.shield.fill",
                            isLoading: viewModel.isLoading
                        ) {
                            Task {
                                let success = await viewModel.validateInvitation(code: viewModel.inviteCode)
                                if success {
                                    navigateToSetup = true
                                }
                            }
                        }

                        Button(action: {
                            isLoginMode = true
                            viewModel.errorMessage = nil
                        }) {
                            Text(L("auth_already_have_account"))
                                .font(AppTypography.subheadline)
                                .foregroundColor(AppColors.accent)
                        }
                        .padding(.top, AppSpacing.xs)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.xl)
            }
            .background(AppColors.background)
            .navigationDestination(isPresented: $navigateToSetup) {
                AccountSetupView(viewModel: viewModel)
            }
        }
    }
}
