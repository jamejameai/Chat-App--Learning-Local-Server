import SwiftUI

/// Real live motion developer badge rendered next to user account name displays.
/// Crafted with a modern, clean, luxury obsidian glass finish, animated glowing sweep,
/// and subtle breathing code brackets. Zero emoji, 100% refined vector motion.
public struct LiveMotionDeveloperBadge: View {
    public let showLabel: Bool
    public let size: CGFloat

    @State private var shimmerPhase: CGFloat = -1.0
    @State private var isPulsing: Bool = false

    public init(showLabel: Bool = false, size: CGFloat = 16) {
        self.showLabel = showLabel
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 3) {
            ZStack {
                // Outer luxury halo
                RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.83, green: 0.69, blue: 0.35).opacity(0.35),
                                Color(red: 0.15, green: 0.16, blue: 0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.96, green: 0.90, blue: 0.72),
                                        Color(red: 0.60, green: 0.44, blue: 0.18).opacity(0.5)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.75
                            )
                    )

                // Animated glowing sweep
                RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: Color.white.opacity(0.4), location: 0.5),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: UnitPoint(x: shimmerPhase, y: shimmerPhase * 0.5),
                            endPoint: UnitPoint(x: shimmerPhase + 0.6, y: shimmerPhase * 0.5 + 0.6)
                        )
                    )
                    .frame(width: size, height: size)
                    .mask(RoundedRectangle(cornerRadius: size * 0.35, style: .continuous))

                // Developer code glyph (modern clean vector `< / >`)
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.94, blue: 0.82),
                                Color(red: 0.83, green: 0.69, blue: 0.35)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(isPulsing ? 1.08 : 0.96)
            }

            if showLabel {
                Text("DEV")
                    .font(.system(size: max(size * 0.55, 9), weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.90, blue: 0.72),
                                Color(red: 0.83, green: 0.69, blue: 0.35)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .padding(.horizontal, showLabel ? 4 : 0)
        .padding(.vertical, showLabel ? 2 : 0)
        .background {
            if showLabel {
                Capsule()
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.85))
                    .overlay(
                        Capsule().stroke(Color(red: 0.83, green: 0.69, blue: 0.35).opacity(0.3), lineWidth: 0.5)
                    )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.6
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .accessibilityLabel("Developer account verified")
    }
}

/// Helper view for rendering display name alongside the developer motion badge and custom luxury name colors
public struct AccountDisplayNameView: View {
    public let name: String
    public let isDeveloper: Bool
    public let isOwner: Bool
    public let font: Font
    public let nameColorHex: String?
    public let baseColor: Color
    public let badgeSize: CGFloat
    public let showBadgeLabel: Bool?

    public init(
        name: String,
        isDeveloper: Bool = false,
        isOwner: Bool = false,
        nameColorHex: String? = nil,
        font: Font = AppTypography.headline,
        color: Color = AppColors.textPrimary,
        badgeSize: CGFloat = 16,
        showBadgeLabel: Bool? = nil
    ) {
        self.name = name
        self.isDeveloper = isDeveloper
        self.isOwner = isOwner
        self.nameColorHex = nameColorHex
        self.font = font
        self.baseColor = color
        self.badgeSize = badgeSize
        self.showBadgeLabel = showBadgeLabel
    }

    private var effectiveColor: Color {
        if let hex = nameColorHex, !hex.isEmpty {
            return NameColorTheme.color(for: hex, fallback: baseColor)
        }
        if isOwner {
            // Owner name defaults to imperial red
            return NameColorTheme.imperialRed.color
        }
        return baseColor
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Text(name)
                .font(font)
                .foregroundColor(effectiveColor)
                .lineLimit(1)

            if isOwner || isDeveloper {
                LiveMotionDeveloperBadge(showLabel: showBadgeLabel ?? isOwner, size: badgeSize)
            }
        }
    }
}
