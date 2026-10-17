import SwiftUI

public struct AccountSetupView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject public var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                VStack(spacing: AppSpacing.xs) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 54))
                        .foregroundColor(AppColors.accent)
                        .padding(.top, AppSpacing.md)

                    Text(L("auth_create_account"))
                        .font(AppTypography.title)
                        .foregroundColor(AppColors.textPrimary)

                    if let invite = viewModel.validatedInvite {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: invite.role == "superadmin" ? "crown.fill" : "person.fill")
                            Text(invite.role == "superadmin" ? "Super-Administrator" : "Team Member")
                        }
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xxs)
                        .background(AppColors.accentLight)
                        .cornerRadius(AppCornerRadius.full)
                    }
                }

                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(AppColors.statusError)
                        Text(error)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.statusError)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Inputs
                VStack(spacing: AppSpacing.md) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(L("auth_username"))
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: L("auth_username_placeholder"),
                            text: $viewModel.username,
                            autocapitalization: .never
                        )
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(L("auth_display_name"))
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: L("auth_display_name_placeholder"),
                            text: $viewModel.displayName
                        )
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(L("auth_password"))
                            .font(AppTypography.footnote.weight(.semibold))
                            .foregroundColor(AppColors.textSecondary)

                        CustomTextField(
                            placeholder: L("auth_password_placeholder"),
                            text: $viewModel.password,
                            isSecure: true
                        )
                    }
                }

                // E2EE Notice
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(AppColors.accent)
                    Text("Device cryptographic identity keys will be generated automatically on your iPhone.")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.horizontal, AppSpacing.xs)

                if let progress = viewModel.keyGenerationProgress {
                    HStack(spacing: AppSpacing.xs) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text(progress)
                            .font(AppTypography.footnote)
                            .foregroundColor(AppColors.accent)
                    }
                }

                PrimaryButton(
                    title: L("auth_create_account"),
                    icon: "checkmark",
                    isLoading: viewModel.isLoading
                ) {
                    Task {
                        _ = await viewModel.register(appState: appState)
                    }
                }
                .padding(.top, AppSpacing.sm)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}
