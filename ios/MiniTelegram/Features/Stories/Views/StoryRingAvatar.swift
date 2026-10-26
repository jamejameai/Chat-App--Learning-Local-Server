import SwiftUI

/// A profile photo with Telegram's story ring: colourful when there's something new, grey once seen.
public struct StoryRingAvatar: View {
    let name: String
    let avatarUrl: String?
    let size: CGFloat
    let ring: StoryRingState
    let borderTemplate: ProfileBorderTemplate

    public static let unseenGradient = AngularGradient(
        colors: [
            AppColors.accent,
            Color(red: 1.0, green: 0.27, blue: 0.53),
            Color(red: 1.0, green: 0.62, blue: 0.0),
            Color(red: 1.0, green: 0.27, blue: 0.53),
            AppColors.accent,
        ],
        center: .center
    )

    public init(
        name: String,
        avatarUrl: String?,
        size: CGFloat,
        ring: StoryRingState,
        borderTemplate: ProfileBorderTemplate = .cleanMinimal
    ) {
        self.name = name
        self.avatarUrl = avatarUrl
        self.size = size
        self.ring = ring
        self.borderTemplate = borderTemplate
    }

    public var body: some View {
        AvatarView(name: name, avatarUrl: avatarUrl, size: size, borderTemplate: borderTemplate)
            .padding(4)
            .overlay {
                switch ring {
                case .unseen:
                    Circle().strokeBorder(Self.unseenGradient, lineWidth: 2.5)
                case .seen:
                    Circle().strokeBorder(AppColors.textTertiary.opacity(0.6), lineWidth: 1.5)
                case .none:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: ring)
    }
}
