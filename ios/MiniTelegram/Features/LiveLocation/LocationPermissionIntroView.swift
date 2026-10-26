import SwiftUI

public struct LocationPermissionIntroView: View {
    let onFinish: () -> Void
    @ObservedObject private var locationManager = LiveLocationManager.shared

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColors.accentLight)
                    .frame(width: 112, height: 112)
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundStyle(AppColors.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("A little closer, wherever you are.")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Allow location access to share your live position with friends. Nothing is shared until you turn on Live Location, and you can stop at any time.")
                    .font(AppTypography.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                privacyRow("person.2.fill", "Only accepted friends can see your live position")
                privacyRow("location.slash.fill", "Your route history is not saved")
                privacyRow("pause.circle.fill", "Stop sharing whenever you like")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground, in: RoundedRectangle(cornerRadius: 20))

            Spacer()

            Button {
                locationManager.requestWhenInUseAuthorization()
                onFinish()
            } label: {
                Text("Continue")
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(AppColors.textPrimary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the system location permission prompt")

            Button("Not now", action: onFinish)
                .font(AppTypography.subheadline.weight(.medium))
                .foregroundStyle(AppColors.textSecondary)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .background(AppColors.background.ignoresSafeArea())
    }

    private func privacyRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}
