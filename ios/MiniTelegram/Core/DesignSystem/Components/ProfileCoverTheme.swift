import SwiftUI

public enum ProfileCoverPreset: String, CaseIterable, Identifiable {
    case obsidian = "cover:obsidian"
    case champagneGold = "cover:champagneGold"
    case platinumMinimal = "cover:platinumMinimal"
    case royalNavy = "cover:royalNavy"
    case emeraldNoir = "cover:emeraldNoir"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .obsidian: return "Obsidian Carbon"
        case .champagneGold: return "Champagne Gold"
        case .platinumMinimal: return "Platinum Minimal"
        case .royalNavy: return "Royal Midnight"
        case .emeraldNoir: return "Emerald Noir"
        }
    }

    public var gradientColors: [Color] {
        switch self {
        case .obsidian:
            return [
                Color(red: 0.16, green: 0.17, blue: 0.20),
                Color(red: 0.08, green: 0.09, blue: 0.10),
                Color(red: 0.12, green: 0.13, blue: 0.15)
            ]
        case .champagneGold:
            return [
                Color(red: 0.75, green: 0.60, blue: 0.32),
                Color(red: 0.45, green: 0.33, blue: 0.16),
                Color(red: 0.25, green: 0.18, blue: 0.08)
            ]
        case .platinumMinimal:
            return [
                Color(red: 0.40, green: 0.42, blue: 0.45),
                Color(red: 0.22, green: 0.23, blue: 0.25),
                Color(red: 0.15, green: 0.16, blue: 0.18)
            ]
        case .royalNavy:
            return [
                Color(red: 0.15, green: 0.25, blue: 0.45),
                Color(red: 0.08, green: 0.12, blue: 0.25),
                Color(red: 0.04, green: 0.06, blue: 0.14)
            ]
        case .emeraldNoir:
            return [
                Color(red: 0.12, green: 0.28, blue: 0.22),
                Color(red: 0.06, green: 0.16, blue: 0.12),
                Color(red: 0.04, green: 0.08, blue: 0.06)
            ]
        }
    }
}

public struct ProfileCoverBannerView: View {
    public let coverUrl: String?
    public let height: CGFloat

    public init(coverUrl: String?, height: CGFloat = 130) {
        self.coverUrl = coverUrl
        self.height = height
    }

    public var body: some View {
        ZStack {
            if let coverUrl, !coverUrl.isEmpty {
                if let preset = ProfileCoverPreset(rawValue: coverUrl) {
                    presetBanner(preset)
                } else if let data = Data(base64Encoded: coverUrl.replacingOccurrences(of: "data:image/jpeg;base64,", with: "").replacingOccurrences(of: "data:image/png;base64,", with: "")),
                          let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: height)
                        .clipped()
                } else {
                    defaultLuxuryBanner
                }
            } else {
                defaultLuxuryBanner
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func presetBanner(_ preset: ProfileCoverPreset) -> some View {
        ZStack {
            LinearGradient(
                colors: preset.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Luxury specular sheen overlay
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.15), location: 0.0),
                    .init(color: Color.clear, location: 0.45),
                    .init(color: Color.black.opacity(0.3), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var defaultLuxuryBanner: some View {
        presetBanner(.obsidian)
    }
}
