import SwiftUI

public struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AuthViewModel
    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var showRegister: Bool = false

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Branding Header
                VStack(spacing: AppSpacing.sm) {
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .cornerRadius(20)
                        .shadow(color: AppColors.accent.opacity(0.25), radius: 12, x: 0, y: 6)
                        .padding(.top, AppSpacing.lg)

                    Text("Welcome Back")
                        .font(AppTypography.largeTitle)
                        .foregroundColor(AppColors.textPrimary)

                    Text("Log in with your username or phone number")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.md)
                }

                // Error Banner
                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(AppColors.statusError)
                        Text(errorMessage)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.statusError)
                    }
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.statusError.opacity(0.1))
                    .cornerRadius(AppCornerRadius.sm)
                    .padding(.horizontal, AppSpacing.lg)
                }

                // Inputs
                VStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Username or Phone Number")
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: "e.g. johndoe or +1234567890",
                            text: $identifier,
                            autocapitalization: .never
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: "Enter your password",
                            text: $password,
                            isSecure: true
                        )
                    }

                    PrimaryButton(
                        title: "Log In",
                        icon: "arrow.right",
                        isLoading: viewModel.isLoading
                    ) {
                        Task {
                            _ = await viewModel.loginWithIdentifier(
                                identifier: identifier,
                                pass: password,
                                appState: appState
                            )
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                }
                .padding(.horizontal, AppSpacing.lg)

                // Footer Switch to Register
                Button(action: {
                    showRegister = true
                }) {
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundColor(AppColors.textSecondary)
                        Text("Sign Up")
                            .fontWeight(.bold)
                            .foregroundColor(AppColors.accent)
                    }
                    .font(AppTypography.subheadline)
                }
                .padding(.top, AppSpacing.md)
            }
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.background)
        .navigationTitle("Log In")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showRegister) {
            RegisterView(viewModel: viewModel)
        }
    }
}
