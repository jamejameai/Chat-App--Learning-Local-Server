import SwiftUI

public enum IllustratedAvatarPreset: String, CaseIterable, Identifiable {
    case sunny
    case fox
    case tiger
    case cat
    case dog
    case lion
    case voyager
    case spark
    case gem
    case star
    case crown
    case scout

    public var id: String { rawValue }

    public var storageValue: String {
        "illustrated-avatar:\(rawValue)"
    }

    public var displayName: String {
        switch self {
        case .sunny: "Sunny"
        case .fox: "Fox"
        case .tiger: "Tiger"
        case .cat: "Cat"
        case .dog: "Dog"
        case .lion: "Lion"
        case .voyager: "Voyager"
        case .spark: "Spark"
        case .gem: "Gem"
        case .star: "Star"
        case .crown: "Crown"
        case .scout: "Scout"
        }
    }

    public init?(storageValue: String) {
        let prefix = "illustrated-avatar:"
        if storageValue.hasPrefix(prefix),
           let preset = Self(rawValue: String(storageValue.dropFirst(prefix.count))) {
            self = preset
            return
        }

        switch storageValue {
        case "😀": self = .sunny
        case "🦊": self = .fox
        case "🐯": self = .tiger
        case "🐱": self = .cat
        case "🐶": self = .dog
        case "🦁": self = .lion
        case "🚀": self = .voyager
        case "⚡️": self = .spark
        case "🔥": self = .spark
        case "💎": self = .gem
        case "🌟": self = .star
        case "👑": self = .crown
        case "🎯": self = .scout
        default: return nil
        }
    }

    fileprivate var artwork: AvatarArtwork {
        switch self {
        case .sunny:
            AvatarArtwork(background: Color(red: 0.98, green: 0.83, blue: 0.56), skin: Color(red: 0.78, green: 0.48, blue: 0.32), hair: Color(red: 0.20, green: 0.15, blue: 0.13), clothing: Color(red: 0.18, green: 0.42, blue: 0.39), hairStyle: .curly)
        case .fox:
            AvatarArtwork(background: Color(red: 0.97, green: 0.77, blue: 0.63), skin: Color(red: 0.91, green: 0.68, blue: 0.51), hair: Color(red: 0.34, green: 0.20, blue: 0.15), clothing: Color(red: 0.80, green: 0.34, blue: 0.23), hairStyle: .wavy)
        case .tiger:
            AvatarArtwork(background: Color(red: 0.95, green: 0.82, blue: 0.59), skin: Color(red: 0.55, green: 0.34, blue: 0.25), hair: Color(red: 0.12, green: 0.10, blue: 0.10), clothing: Color(red: 0.30, green: 0.39, blue: 0.62), hairStyle: .short)
        case .cat:
            AvatarArtwork(background: Color(red: 0.83, green: 0.84, blue: 0.96), skin: Color(red: 0.96, green: 0.76, blue: 0.62), hair: Color(red: 0.22, green: 0.18, blue: 0.22), clothing: Color(red: 0.49, green: 0.35, blue: 0.62), hairStyle: .long)
        case .dog:
            AvatarArtwork(background: Color(red: 0.76, green: 0.88, blue: 0.86), skin: Color(red: 0.72, green: 0.48, blue: 0.34), hair: Color(red: 0.18, green: 0.13, blue: 0.12), clothing: Color(red: 0.18, green: 0.47, blue: 0.45), hairStyle: .short)
        case .lion:
            AvatarArtwork(background: Color(red: 0.96, green: 0.81, blue: 0.63), skin: Color(red: 0.94, green: 0.70, blue: 0.53), hair: Color(red: 0.52, green: 0.31, blue: 0.18), clothing: Color(red: 0.72, green: 0.40, blue: 0.25), hairStyle: .curly)
        case .voyager:
            AvatarArtwork(background: Color(red: 0.73, green: 0.83, blue: 0.94), skin: Color(red: 0.91, green: 0.71, blue: 0.57), hair: Color(red: 0.18, green: 0.15, blue: 0.18), clothing: Color(red: 0.29, green: 0.40, blue: 0.66), hairStyle: .short)
        case .spark:
            AvatarArtwork(background: Color(red: 0.94, green: 0.80, blue: 0.84), skin: Color(red: 0.48, green: 0.30, blue: 0.24), hair: Color(red: 0.13, green: 0.12, blue: 0.17), clothing: Color(red: 0.68, green: 0.32, blue: 0.43), hairStyle: .wavy)
        case .gem:
            AvatarArtwork(background: Color(red: 0.73, green: 0.87, blue: 0.89), skin: Color(red: 0.95, green: 0.77, blue: 0.63), hair: Color(red: 0.29, green: 0.19, blue: 0.15), clothing: Color(red: 0.21, green: 0.49, blue: 0.59), hairStyle: .long)
        case .star:
            AvatarArtwork(background: Color(red: 0.91, green: 0.85, blue: 0.68), skin: Color(red: 0.72, green: 0.46, blue: 0.34), hair: Color(red: 0.15, green: 0.12, blue: 0.13), clothing: Color(red: 0.36, green: 0.47, blue: 0.36), hairStyle: .curly)
        case .crown:
            AvatarArtwork(background: Color(red: 0.83, green: 0.78, blue: 0.91), skin: Color(red: 0.88, green: 0.65, blue: 0.48), hair: Color(red: 0.27, green: 0.17, blue: 0.13), clothing: Color(red: 0.47, green: 0.32, blue: 0.60), hairStyle: .long)
        case .scout:
            AvatarArtwork(background: Color(red: 0.78, green: 0.87, blue: 0.72), skin: Color(red: 0.60, green: 0.38, blue: 0.28), hair: Color(red: 0.16, green: 0.12, blue: 0.10), clothing: Color(red: 0.49, green: 0.45, blue: 0.25), hairStyle: .wavy)
        }
    }
}

private enum AvatarHairStyle: Equatable {
    case short
    case wavy
    case curly
    case long
}

private struct AvatarArtwork {
    let background: Color
    let skin: Color
    let hair: Color
    let clothing: Color
    let hairStyle: AvatarHairStyle
}

public struct IllustratedAvatarView: View {
    public let preset: IllustratedAvatarPreset
    public let size: CGFloat

    public init(preset: IllustratedAvatarPreset, size: CGFloat) {
        self.preset = preset
        self.size = size
    }

    public var body: some View {
        let art = preset.artwork

        ZStack {
            Circle().fill(art.background)

            if art.hairStyle == .long {
                Ellipse()
                    .fill(art.hair)
                    .frame(width: size * 0.59, height: size * 0.71)
                    .offset(y: size * 0.06)
            }

            Ellipse()
                .fill(art.clothing)
                .frame(width: size * 0.84, height: size * 0.57)
                .offset(y: size * 0.48)

            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(art.skin)
                .frame(width: size * 0.18, height: size * 0.2)
                .offset(y: size * 0.29)

            HStack(spacing: size * 0.34) {
                Circle().fill(art.skin)
                Circle().fill(art.skin)
            }
            .frame(width: size * 0.57, height: size * 0.15)
            .offset(y: size * 0.01)

            Ellipse()
                .fill(art.skin)
                .frame(width: size * 0.49, height: size * 0.58)
                .offset(y: size * 0.015)

            hairShape(style: art.hairStyle, color: art.hair)
                .frame(width: size * 0.58, height: size * 0.32)
                .offset(y: -size * 0.19)

            HStack(spacing: size * 0.16) {
                eye(size: size)
                eye(size: size)
            }
            .offset(y: -size * 0.015)

            Ellipse()
                .fill(Color(red: 0.45, green: 0.25, blue: 0.22).opacity(0.35))
                .frame(width: size * 0.045, height: size * 0.07)
                .offset(y: size * 0.06)

            SmileShape()
                .stroke(Color(red: 0.39, green: 0.19, blue: 0.19), style: StrokeStyle(lineWidth: max(size * 0.018, 1.2), lineCap: .round))
                .frame(width: size * 0.15, height: size * 0.07)
                .offset(y: size * 0.14)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func hairShape(style: AvatarHairStyle, color: Color) -> some View {
        switch style {
        case .curly:
            ZStack {
                Ellipse().fill(color).offset(y: size * 0.025)
                HStack(spacing: size * 0.025) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle().fill(color)
                    }
                }
                .frame(height: size * 0.2)
                .offset(y: -size * 0.06)
            }
        case .wavy:
            ZStack {
                Ellipse().fill(color)
                Ellipse().fill(color)
                    .frame(width: size * 0.25, height: size * 0.17)
                    .rotationEffect(.degrees(-18))
                    .offset(x: -size * 0.14, y: size * 0.08)
            }
        case .short, .long:
            Ellipse().fill(color)
        }
    }

    private func eye(size: CGFloat) -> some View {
        Circle()
            .fill(Color(red: 0.16, green: 0.13, blue: 0.13))
            .frame(width: size * 0.045, height: size * 0.045)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: size * 0.014, height: size * 0.014)
                    .offset(x: -size * 0.008, y: size * 0.006)
            }
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

public struct IllustratedAvatarPicker: View {
    @Binding private var selection: String?

    public init(selection: Binding<String?>) {
        _selection = selection
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 3)

    public var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.md) {
            ForEach(IllustratedAvatarPreset.allCases) { preset in
                let isSelected = IllustratedAvatarPreset(storageValue: selection ?? "") == preset

                Button {
                    selection = preset.storageValue
                } label: {
                    VStack(spacing: AppSpacing.xs) {
                        IllustratedAvatarView(preset: preset, size: 62)
                            .overlay {
                                Circle()
                                    .stroke(isSelected ? AppColors.accent : AppColors.border, lineWidth: isSelected ? 3 : 1)
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, AppColors.accent)
                                        .offset(x: 3, y: 3)
                                }
                            }

                        Text(preset.displayName)
                            .font(AppTypography.caption.weight(.medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 88)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose \(preset.displayName) avatar")
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

public struct AvatarView: View {
    public let name: String
    public let avatarUrl: String?
    public let size: CGFloat
    public let isOnline: Bool
    public let borderTemplate: ProfileBorderTemplate

    public init(
        name: String,
        avatarUrl: String? = nil,
        size: CGFloat = 48,
        isOnline: Bool = false,
        borderTemplate: ProfileBorderTemplate = .cleanMinimal
    ) {
        self.name = name
        self.avatarUrl = avatarUrl
        self.size = size
        self.isOnline = isOnline
        self.borderTemplate = borderTemplate
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
            Group {
                if let avatar = avatarUrl, !avatar.isEmpty {
                    if let preset = IllustratedAvatarPreset(storageValue: avatar) {
                        IllustratedAvatarView(preset: preset, size: size)
                    } else if let data = Data(base64Encoded: avatar.replacingOccurrences(of: "data:image/jpeg;base64,", with: "").replacingOccurrences(of: "data:image/png;base64,", with: "")),
                       let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else {
                        defaultAvatar
                    }
                } else {
                    defaultAvatar
                }
            }
            .profileBorder(borderTemplate, size: size)

            if isOnline {
                Circle()
                    .fill(AppColors.statusOnline)
                    .frame(width: max(size * 0.28, 10), height: max(size * 0.28, 10))
                    .overlay(
                        Circle()
                            .stroke(AppColors.background, lineWidth: 2)
                    )
                    .offset(x: 1, y: 1)
            }
        }
    }

    private var defaultAvatar: some View {
        Circle()
            .fill(LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.20, blue: 0.24),
                    Color(red: 0.10, green: 0.11, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.96, green: 0.90, blue: 0.72))
            )
    }
}

/// Modern clean luxury border template picker for EditProfileSheet
public struct ProfileBorderTemplatePicker: View {
    @Binding public var selection: String
    public let avatarName: String
    public let avatarUrl: String?

    public init(selection: Binding<String>, avatarName: String, avatarUrl: String?) {
        self._selection = selection
        self.avatarName = avatarName
        self.avatarUrl = avatarUrl
    }

    private let columns = [
        GridItem(.adaptive(minimum: 95, maximum: 120), spacing: 12)
    ]

    public var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(ProfileBorderTemplate.allCases) { template in
                let isSelected = selection == template.rawValue || (selection.isEmpty && template == .platinumExecutive)
                Button {
                    selection = template.rawValue
                } label: {
                    VStack(spacing: 8) {
                        AvatarView(
                            name: avatarName,
                            avatarUrl: avatarUrl,
                            size: 56,
                            isOnline: false,
                            borderTemplate: template
                        )

                        Text(template.displayName)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous)
                            .fill(isSelected ? Color(red: 0.83, green: 0.69, blue: 0.35).opacity(0.12) : AppColors.secondaryBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous)
                            .stroke(isSelected ? Color(red: 0.83, green: 0.69, blue: 0.35) : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

