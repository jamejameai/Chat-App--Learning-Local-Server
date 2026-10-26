import SwiftUI

extension Notification.Name {
    /// Posted when a chat's theme changes; `object` is the conversation id.
    public static let chatThemeChanged = Notification.Name("OurChat.chatThemeChanged")
}

/// A chat look: background, my bubbles, their bubbles. 30 built-in themes, chosen per chat.
public struct ChatTheme: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Chat background gradient (top → bottom)
    public let background: [Color]
    /// My bubbles (gradient) and text
    public let outgoing: [Color]
    public let outgoingText: Color
    /// Their bubbles and text
    public let incoming: Color
    public let incomingText: Color
    /// Date pills, "Seen", sender names
    public let accent: Color
    public let isDark: Bool

    public var outgoingMeta: Color { outgoingText.opacity(0.72) }
    public var incomingMeta: Color { incomingText.opacity(0.55) }

    // Colours for everything drawn straight on the chat background, so text always contrasts
    /// Text on the background (header title, empty states)
    public var foreground: Color { isDark ? Self.hex(0xF2F2F7) : Self.hex(0x1C1C1E) }
    public var secondaryForeground: Color { foreground.opacity(isDark ? 0.62 : 0.55) }
    /// Floating cards: composer, date pills, reactions
    public var surface: Color { isDark ? incoming : .white }
    public var surfaceText: Color { incomingText }
    public var border: Color { isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07) }
    /// Top bar, matching the top of the background
    public var barBackground: Color { background.first ?? .clear }
    /// Send button and other "primary" buttons use my bubble colours
    public var actionGradient: LinearGradient {
        LinearGradient(colors: outgoing, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Per-chat choice (stored on this phone)

    private static func key(_ conversationId: String) -> String { "chat_theme.\(conversationId)" }

    public static func theme(for conversationId: String) -> ChatTheme {
        let id = UserDefaults.standard.string(forKey: key(conversationId))
        return all.first { $0.id == id } ?? .classic
    }

    public static func setTheme(_ theme: ChatTheme, for conversationId: String) {
        UserDefaults.standard.set(theme.id, forKey: key(conversationId))
        NotificationCenter.default.post(name: .chatThemeChanged, object: conversationId)
    }

    // MARK: - The 30 themes

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func light(_ id: String, _ name: String, bg: [UInt32], out: [UInt32], inc: UInt32 = 0xFFFFFF, accent: UInt32) -> ChatTheme {
        ChatTheme(
            id: id, name: name,
            background: bg.map(hex),
            outgoing: out.map(hex), outgoingText: .white,
            incoming: hex(inc), incomingText: hex(0x1C1C1E),
            accent: hex(accent), isDark: false
        )
    }

    private static func dark(_ id: String, _ name: String, bg: [UInt32], out: [UInt32], inc: UInt32, accent: UInt32) -> ChatTheme {
        ChatTheme(
            id: id, name: name,
            background: bg.map(hex),
            outgoing: out.map(hex), outgoingText: .white,
            incoming: hex(inc), incomingText: hex(0xF2F2F7),
            accent: hex(accent), isDark: true
        )
    }

    public static let classic = light("classic", "Classic", bg: [0xEEF3F8, 0xE3EBF3], out: [0x2AABEE, 0x229ED9], accent: 0x229ED9)

    public static let all: [ChatTheme] = [
        classic,
        light("sky", "Sky", bg: [0xE6F4FF, 0xCFE8FF], out: [0x4FACFE, 0x00C6FB], accent: 0x1E88E5),
        light("mint", "Mint", bg: [0xE8FBF3, 0xD2F5E6], out: [0x11998E, 0x38EF7D], accent: 0x0F9D58),
        light("peach", "Peach", bg: [0xFFF1E8, 0xFFE0CC], out: [0xFF8A5B, 0xFF6A88], accent: 0xF4511E),
        light("lavender", "Lavender", bg: [0xF3EEFF, 0xE6DCFF], out: [0x8E54E9, 0x4776E6], accent: 0x7E57C2),
        light("rose", "Rose", bg: [0xFFF0F5, 0xFFDDE8], out: [0xF857A6, 0xFF5858], accent: 0xD81B60),
        light("lemon", "Lemon", bg: [0xFFFBE6, 0xFFF3BF], out: [0xF7971E, 0xFFB300], accent: 0xF57C00),
        light("ocean", "Ocean", bg: [0xE0F7FA, 0xB2EBF2], out: [0x0083B0, 0x00B4DB], accent: 0x00838F),
        light("sakura", "Sakura", bg: [0xFDEFF4, 0xF8D7E3], out: [0xEE9CA7, 0xD66D75], accent: 0xC2185B),
        light("sand", "Sand", bg: [0xFAF3E8, 0xF0E2CB], out: [0xC79A63, 0xA9743F], accent: 0x8D6E63),
        light("forest", "Forest", bg: [0xEDF5EC, 0xD8EAD5], out: [0x2E7D32, 0x43A047], accent: 0x2E7D32),
        light("sunset", "Sunset", bg: [0xFFF3E0, 0xFFE3E3], out: [0xFF512F, 0xDD2476], accent: 0xE64A19),
        light("aqua", "Aqua", bg: [0xE9FFFB, 0xC9F7EF], out: [0x13B6C1, 0x00A88F], accent: 0x00897B),
        light("berry", "Berry", bg: [0xF8EEFB, 0xEBD7F2], out: [0x9C27B0, 0xE040FB], accent: 0x8E24AA),
        light("graphite", "Graphite", bg: [0xF2F3F5, 0xE4E6EA], out: [0x434343, 0x6B6B6B], accent: 0x455A64),
        light("coral", "Coral", bg: [0xFFF2EE, 0xFFDCD2], out: [0xFF7E5F, 0xFEB47B], accent: 0xFF7043),
        light("ice", "Ice", bg: [0xF5FBFF, 0xE3F2FD], out: [0x6DD5ED, 0x2193B0], accent: 0x0288D1),
        light("matcha", "Matcha", bg: [0xF3F8E9, 0xE1EECB], out: [0x7FB069, 0x5C8D3E], accent: 0x689F38),
        light("royal", "Royal", bg: [0xEEF0FF, 0xDCE1FF], out: [0x3F51B5, 0x5C6BC0], accent: 0x3949AB),
        light("candy", "Candy", bg: [0xFFF0FB, 0xF0E4FF], out: [0xFC5C7D, 0x6A82FB], accent: 0xAB47BC),
        dark("midnight", "Midnight", bg: [0x0F1724, 0x15202F], out: [0x2AABEE, 0x1E88E5], inc: 0x22303F, accent: 0x64B5F6),
        dark("night-mint", "Night Mint", bg: [0x0C1A17, 0x12261F], out: [0x00B894, 0x00897B], inc: 0x1E3330, accent: 0x4DD0A8),
        dark("galaxy", "Galaxy", bg: [0x120E26, 0x241B45], out: [0x7F00FF, 0xE100FF], inc: 0x2C2450, accent: 0xB388FF),
        dark("ember", "Ember", bg: [0x1A0E0B, 0x2B1510], out: [0xF12711, 0xF5AF19], inc: 0x3A221B, accent: 0xFFAB40),
        dark("noir", "Noir", bg: [0x0A0A0A, 0x1A1A1A], out: [0x3A3A3C, 0x48484A], inc: 0x242426, accent: 0xBDBDBD),
        dark("deep-sea", "Deep Sea", bg: [0x041C2C, 0x06324B], out: [0x00C6FF, 0x0072FF], inc: 0x0E3A55, accent: 0x4FC3F7),
        dark("aurora", "Aurora", bg: [0x061A1A, 0x0B2E2B], out: [0x43CEA2, 0x185A9D], inc: 0x16403C, accent: 0x69F0AE),
        dark("wine", "Wine", bg: [0x1C0A12, 0x2E0F1E], out: [0xC2185B, 0x880E4F], inc: 0x3B1A2A, accent: 0xF48FB1),
        dark("neon", "Neon", bg: [0x0B0B12, 0x14142A], out: [0xFF00CC, 0x3333FF], inc: 0x1F1F3A, accent: 0x18FFFF),
        dark("cocoa", "Cocoa", bg: [0x1B130F, 0x2A1E17], out: [0xA0522D, 0x8B4513], inc: 0x3A2B22, accent: 0xD7A86E),
    ]
}

// The chat's theme for nested views (voice notes, files, composer) without threading it through
private struct ChatThemeKey: EnvironmentKey {
    static let defaultValue: ChatTheme = .classic
}

extension EnvironmentValues {
    public var chatTheme: ChatTheme {
        get { self[ChatThemeKey.self] }
        set { self[ChatThemeKey.self] = newValue }
    }
}
