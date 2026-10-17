import SwiftUI

public struct IncomingCallBannerView: View {
    public let callItem: CallItem
    public let onAccept: () -> Void
    public let onDecline: () -> Void

    public init(
        callItem: CallItem,
        onAccept: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.callItem = callItem
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            AvatarView(name: callItem.callerName, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(callItem.callerName)
                    .font(AppTypography.headline)
                    .foregroundColor(AppColors.textPrimary)

                HStack(spacing: 4) {
                    Image(systemName: callItem.callType == .video ? "video.fill" : "phone.fill")
                        .font(.system(size: 11))
                    Text(callItem.callType == .video ? "Incoming Video Call" : "Incoming Audio Call")
                        .font(AppTypography.caption)
                }
                .foregroundColor(AppColors.accent)
            }

            Spacer()

            // Decline Button
            Button(action: onDecline) {
                ZStack {
                    Circle()
                        .fill(AppColors.statusError)
                        .frame(width: 40, height: 40)

                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }

            // Accept Button
            Button(action: onAccept) {
                ZStack {
                    Circle()
                        .fill(AppColors.statusOnline)
                        .frame(width: 40, height: 40)

                    Image(systemName: "phone.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.surface)
        .cornerRadius(AppCornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.lg)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.horizontal, AppSpacing.sm)
    }
}
