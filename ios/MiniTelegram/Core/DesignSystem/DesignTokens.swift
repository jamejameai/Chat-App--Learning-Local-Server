import SwiftUI

public enum AppColors {
    // Primary Brand Red Accent (Subtle, refined)
    public static let accent = Color(red: 229 / 255, green: 57 / 255, blue: 53 / 255) // #E53935
    public static let accentDark = Color(red: 198 / 255, green: 40 / 255, blue: 40 / 255) // #C62828
    public static let accentLight = Color(red: 255 / 255, green: 235 / 255, blue: 238 / 255) // #FFEBEE

    // Surfaces & Backgrounds
    public static let background = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.systemBackground : UIColor.white
    })

    public static let secondaryBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.secondarySystemBackground : UIColor(red: 245/255, green: 245/255, blue: 247/255, alpha: 1.0) // #F5F5F7
    })

    public static let tertiaryBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.tertiarySystemBackground : UIColor(red: 229/255, green: 229/255, blue: 234/255, alpha: 1.0) // #E5E5EA
    })

    // Text & Foreground
    public static let textPrimary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.white : UIColor(red: 17/255, green: 24/255, blue: 39/255, alpha: 1.0) // #111827
    })

    public static let textSecondary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.lightGray : UIColor(red: 107/255, green: 114/255, blue: 128/255, alpha: 1.0) // #6B7280
    })

    public static let textTertiary = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor.darkGray : UIColor(red: 156/255, green: 163/255, blue: 175/255, alpha: 1.0) // #9CA3AF
    })

    // Status Colors
    public static let statusOnline = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255) // #34C759
    public static let statusError = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    public static let statusWarning = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)

    // Message Bubbles
    public static let outgoingBubble = accent
    public static let outgoingText = Color.white
    public static let incomingBubble = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(red: 44/255, green: 44/255, blue: 46/255, alpha: 1.0) : UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1.0)
    })
    public static let incomingText = textPrimary

    // Separators & Borders
    public static let border = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(white: 0.25, alpha: 1.0) : UIColor(red: 229/255, green: 231/255, blue: 235/255, alpha: 1.0)
    })
}

public enum AppSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum AppCornerRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let bubble: CGFloat = 18
    public static let full: CGFloat = 999
}

public enum AppTypography {
    public static let largeTitle: Font = .system(.largeTitle, design: .default).weight(.bold)
    public static let title: Font = .system(.title, design: .default).weight(.semibold)
    public static let headline: Font = .system(.headline, design: .default).weight(.semibold)
    public static let body: Font = .system(.body, design: .default)
    public static let subheadline: Font = .system(.subheadline, design: .default)
    public static let footnote: Font = .system(.footnote, design: .default)
    public static let caption: Font = .system(.caption, design: .default)
}
