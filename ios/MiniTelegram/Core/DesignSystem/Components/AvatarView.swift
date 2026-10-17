import SwiftUI

public struct AvatarView: View {
    public let name: String
    public let avatarUrl: String?
    public let size: CGFloat
    public let isOnline: Bool

    public init(name: String, avatarUrl: String? = nil, size: CGFloat = 48, isOnline: Bool = false) {
        self.name = name
        self.avatarUrl = avatarUrl
        self.size = size
        self.isOnline = isOnline
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2, let first = parts[0].first, let second = parts[1].first {
            return "\(first)\(second)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "MT"
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(AppColors.secondaryBackground)
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundColor(AppColors.textSecondary)
                )

            if isOnline {
                Circle()
                    .fill(AppColors.statusOnline)
                    .frame(width: size * 0.28, height: size * 0.28)
                    .overlay(
                        Circle()
                            .stroke(AppColors.background, lineWidth: 2)
                    )
                    .offset(x: 1, y: 1)
            }
        }
    }
}
