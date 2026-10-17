import SwiftUI

public struct LoadingView: View {
    public let message: String

    public init(message: String? = nil) {
        self.message = message ?? L("state_loading")
    }

    public var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent))
            Text(message)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}

public struct EmptyStateView: View {
    public let icon: String
    public let title: String
    public let description: String
    public let actionTitle: String?
    public let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        description: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(AppColors.textTertiary)
                .padding(.bottom, AppSpacing.xs)

            Text(title)
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(description)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xl)

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(AppTypography.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.accentLight)
                        .cornerRadius(AppCornerRadius.full)
                }
                .padding(.top, AppSpacing.xs)
            }
        }
        .padding(AppSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}

public struct ErrorStateView: View {
    public let title: String
    public let message: String
    public let retryAction: (() -> Void)?

    public init(
        title: String? = nil,
        message: String,
        retryAction: (() -> Void)? = nil
    ) {
        self.title = title ?? L("state_error_title")
        self.message = message
        self.retryAction = retryAction
    }

    public var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(AppColors.statusWarning)

            Text(title)
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)

            Text(message)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)

            if let retryAction = retryAction {
                Button(action: retryAction) {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "arrow.clockwise")
                        Text(L("action_retry"))
                    }
                    .font(AppTypography.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.accent)
                }
                .padding(.top, AppSpacing.xs)
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }
}
