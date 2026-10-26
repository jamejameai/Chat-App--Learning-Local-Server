import SwiftUI

public enum ProfileBorderTemplate: String, CaseIterable, Identifiable, Codable, Sendable {
    case cleanMinimal = "cleanMinimal"
    case goldLeaf = "goldLeaf"
    case platinumExecutive = "platinumExecutive"
    case obsidianNoir = "obsidianNoir"
    case royalMidnight = "royalMidnight"
    case celestialAura = "celestialAura"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cleanMinimal: return "Modern Clean"
        case .goldLeaf: return "Luxury Gold"
        case .platinumExecutive: return "Executive Platinum"
        case .obsidianNoir: return "Obsidian Noir"
        case .royalMidnight: return "Royal Midnight"
        case .celestialAura: return "Celestial Aura"
        }
    }

    public var description: String {
        switch self {
        case .cleanMinimal: return "Restrained, crisp minimalist platinum hairline rim."
        case .goldLeaf: return "Brushed champagne gold with soft specular reflection."
        case .platinumExecutive: return "Dual-ring architectural titanium and platinum."
        case .obsidianNoir: return "Deep obsidian dark glass with razor specular highlight."
        case .royalMidnight: return "Deep midnight sapphire and brushed slate titanium."
        case .celestialAura: return "Translucent frosted crystal with subtle iridescent sheen."
        }
    }

    public static func from(raw: String?) -> ProfileBorderTemplate {
        guard let raw, !raw.isEmpty else { return .platinumExecutive }
        return ProfileBorderTemplate(rawValue: raw) ?? .platinumExecutive
    }
}

public struct LuxuryBorderModifier: ViewModifier {
    public let template: ProfileBorderTemplate
    public let size: CGFloat

    private var strokeWidth: CGFloat {
        max(size * 0.045, 2.0)
    }

    public func body(content: Content) -> some View {
        content
            .overlay {
                borderOverlay
            }
            .clipShape(Circle())
            .padding(strokeWidth * 0.8)
            .background {
                borderBackground
            }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch template {
        case .cleanMinimal:
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.85), Color.black.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )

        case .goldLeaf:
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.90, blue: 0.72), // Light Champagne Gold
                            Color(red: 0.83, green: 0.69, blue: 0.35), // Pure Gold
                            Color(red: 0.60, green: 0.44, blue: 0.18), // Deep Bronze Gold
                            Color(red: 0.96, green: 0.90, blue: 0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
                .shadow(color: Color(red: 0.83, green: 0.69, blue: 0.35).opacity(0.35), radius: 3, x: 0, y: 1)

        case .platinumExecutive:
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(white: 0.95),
                                Color(white: 0.75),
                                Color(white: 0.50),
                                Color(white: 0.90)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strokeWidth
                    )
                Circle()
                    .stroke(Color.black.opacity(0.2), lineWidth: 0.75)
                    .padding(strokeWidth * 0.4)
            }

        case .obsidianNoir:
            ZStack {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.35, green: 0.38, blue: 0.42),
                                Color(red: 0.12, green: 0.13, blue: 0.15),
                                Color(red: 0.05, green: 0.05, blue: 0.06),
                                Color(red: 0.28, green: 0.30, blue: 0.34)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strokeWidth
                    )
            }
            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)

        case .royalMidnight:
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.35, green: 0.50, blue: 0.85),
                            Color(red: 0.10, green: 0.20, blue: 0.48),
                            Color(red: 0.04, green: 0.08, blue: 0.22),
                            Color(red: 0.25, green: 0.38, blue: 0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
                .shadow(color: Color(red: 0.15, green: 0.25, blue: 0.55).opacity(0.3), radius: 3, x: 0, y: 1)

        case .celestialAura:
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.88, green: 0.90, blue: 0.98),
                            Color(red: 0.78, green: 0.82, blue: 0.92),
                            Color(red: 0.92, green: 0.85, blue: 0.88),
                            Color(red: 0.85, green: 0.92, blue: 0.95)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
                .shadow(color: Color.white.opacity(0.4), radius: 3, x: 0, y: 0)
        }
    }

    @ViewBuilder
    private var borderBackground: some View {
        switch template {
        case .cleanMinimal:
            Circle().fill(Color.clear)
        case .goldLeaf:
            Circle().fill(Color(red: 0.96, green: 0.90, blue: 0.72).opacity(0.12))
        case .platinumExecutive:
            Circle().fill(Color(white: 0.92).opacity(0.15))
        case .obsidianNoir:
            Circle().fill(Color.black.opacity(0.2))
        case .royalMidnight:
            Circle().fill(Color(red: 0.10, green: 0.20, blue: 0.48).opacity(0.15))
        case .celestialAura:
            Circle().fill(Color.white.opacity(0.1))
        }
    }
}

public extension View {
    func profileBorder(_ template: ProfileBorderTemplate, size: CGFloat) -> some View {
        self.modifier(LuxuryBorderModifier(template: template, size: size))
    }
}
