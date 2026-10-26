import SwiftUI

/// Luxury curated name color palette for user display names.
/// App Owner defaults to Imperial Red (#FF3B30) and can change to any luxury preset.
public struct NameColorPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let hex: String
    public let color: Color

    public init(id: String, name: String, hex: String, color: Color) {
        self.id = id
        self.name = name
        self.hex = hex
        self.color = color
    }
}

public enum NameColorTheme {
    public static let imperialRed = NameColorPreset(
        id: "imperialRed",
        name: "Imperial Red",
        hex: "#FF3B30",
        color: Color(red: 1.0, green: 0.23, blue: 0.19)
    )

    public static let electricSapphire = NameColorPreset(
        id: "electricSapphire",
        name: "Sapphire",
        hex: "#007AFF",
        color: Color(red: 0.0, green: 0.48, blue: 1.0)
    )

    public static let royalEmerald = NameColorPreset(
        id: "royalEmerald",
        name: "Emerald",
        hex: "#34C759",
        color: Color(red: 0.20, green: 0.78, blue: 0.35)
    )

    public static let champagneGold = NameColorPreset(
        id: "champagneGold",
        name: "Champagne Gold",
        hex: "#FFD700",
        color: Color(red: 1.0, green: 0.84, blue: 0.0)
    )

    public static let obsidianPlatinum = NameColorPreset(
        id: "obsidianPlatinum",
        name: "Platinum",
        hex: "#E5E5EA",
        color: Color(red: 0.90, green: 0.90, blue: 0.92)
    )

    public static let celestialViolet = NameColorPreset(
        id: "celestialViolet",
        name: "Celestial Violet",
        hex: "#AF52DE",
        color: Color(red: 0.69, green: 0.32, blue: 0.87)
    )

    public static let sunsetAmber = NameColorPreset(
        id: "sunsetAmber",
        name: "Sunset Amber",
        hex: "#FF9500",
        color: Color(red: 1.0, green: 0.58, blue: 0.0)
    )

    public static let roseGold = NameColorPreset(
        id: "roseGold",
        name: "Rose Quartz",
        hex: "#FF2D55",
        color: Color(red: 1.0, green: 0.18, blue: 0.33)
    )

    public static let allPresets: [NameColorPreset] = [
        imperialRed,
        champagneGold,
        electricSapphire,
        royalEmerald,
        celestialViolet,
        sunsetAmber,
        roseGold,
        obsidianPlatinum
    ]

    public static func color(for hex: String?, fallback: Color = AppColors.textPrimary) -> Color {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return fallback
        }

        // Check presets first
        if let preset = allPresets.first(where: { $0.hex.caseInsensitiveCompare(hex) == .orderedSame || $0.id.caseInsensitiveCompare(hex) == .orderedSame }) {
            return preset.color
        }

        // Parse custom Hex string
        var cleanHex = hex.replacingOccurrences(of: "#", with: "")
        if cleanHex.count == 6 {
            cleanHex += "FF"
        }
        guard cleanHex.count == 8, let intVal = UInt64(cleanHex, radix: 16) else {
            return fallback
        }

        let r = Double((intVal >> 24) & 0xFF) / 255.0
        let g = Double((intVal >> 16) & 0xFF) / 255.0
        let b = Double((intVal >> 8) & 0xFF) / 255.0
        let a = Double(intVal & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
