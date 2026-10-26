import SwiftUI

/// Profile header shared by "my profile" and other people's profiles: a modern luxury cover banner with a large
/// ringed photo overlapping its bottom edge, then name with live motion developer badge, @username and bio.
public struct ProfileHeaderView: View {
    let name: String
    let username: String?
    let avatarUrl: String?
    let coverUrl: String?
    let borderTemplate: ProfileBorderTemplate
    let bio: String?
    var isOnline: Bool = false
    var isDeveloper: Bool = false
    var isOwner: Bool = false
    var nameColor: String? = nil

    private let avatarSize: CGFloat = 104

    public init(
        name: String,
        username: String?,
        avatarUrl: String?,
        coverUrl: String? = nil,
        borderTemplate: ProfileBorderTemplate = .platinumExecutive,
        bio: String?,
        isOnline: Bool = false,
        isDeveloper: Bool = false,
        isOwner: Bool = false,
        nameColor: String? = nil
    ) {
        self.name = name
        self.username = username
        self.avatarUrl = avatarUrl
        self.coverUrl = coverUrl
        self.borderTemplate = borderTemplate
        self.bio = bio
        self.isOnline = isOnline
        self.isDeveloper = isDeveloper
        self.isOwner = isOwner
        self.nameColor = nameColor
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                ProfileCoverBannerView(coverUrl: coverUrl, height: 130)

                AvatarView(
                    name: name,
                    avatarUrl: avatarUrl,
                    size: avatarSize,
                    isOnline: isOnline,
                    borderTemplate: borderTemplate
                )
                .padding(4)
                .background(Circle().fill(AppColors.background))
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 5)
                .offset(y: avatarSize / 2)
            }
            .padding(.bottom, avatarSize / 2)

            VStack(spacing: 5) {
                AccountDisplayNameView(
                    name: name,
                    isDeveloper: isDeveloper,
                    isOwner: isOwner,
                    nameColorHex: nameColor,
                    font: AppTypography.title2,
                    color: AppColors.textPrimary,
                    badgeSize: 18,
                    showBadgeLabel: isOwner
                )

                if let username, !username.isEmpty {
                    Text("@\(username)")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }

                if let bio, !bio.isEmpty {
                    Text(bio)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .padding(.horizontal, AppSpacing.lg)
                }
            }
            .padding(.top, AppSpacing.sm)
        }
    }
}


/// Wide pill-shaped action (Message, Add Friend, Edit Profile...).
public struct ProfileActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = AppColors.accent
    var filled: Bool = false
    let action: () -> Void

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(AppTypography.subheadline.weight(.semibold))
            }
            .foregroundColor(filled ? .white : tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(filled ? tint : tint.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A number with a caption (e.g. "12 Friends").
public struct ProfileStatView: View {
    let value: String
    let label: String

    public var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textPrimary)
            Text(label)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous))
    }
}

/// One line of the info card: icon, label, value.
public struct ProfileInfoRow: View {
    let systemImage: String
    let title: String
    let value: String

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.accent)
                .frame(width: 30, height: 30)
                .background(AppColors.accentLight)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(AppTypography.subheadline)
                .foregroundColor(AppColors.textSecondary)
            Spacer(minLength: AppSpacing.sm)
            Text(value)
                .font(AppTypography.subheadline.weight(.medium))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 10)
    }
}

/// Rounded card that stacks ProfileInfoRows.
public struct ProfileInfoCard<Content: View>: View {
    @ViewBuilder let content: Content

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md, style: .continuous))
    }
}

public struct DeveloperProfileSections: View {
    let profile: DeveloperProfile
    var showsEmptyState = false

    private var pinnedProjects: [DeveloperProject] {
        profile.projects.filter(\.isPinned)
    }

    private var hasContent: Bool {
        profile.headline?.isEmpty == false ||
            !profile.skills.isEmpty ||
            !pinnedProjects.isEmpty ||
            profile.websiteURL?.isEmpty == false ||
            profile.githubURL?.isEmpty == false ||
            profile.socialLinks.linkedinURL?.isEmpty == false ||
            profile.socialLinks.instagramURL?.isEmpty == false ||
            profile.socialLinks.xURL?.isEmpty == false ||
            profile.currentlyBuilding?.isEmpty == false ||
            profile.workAvailability?.isEmpty == false ||
            profile.location?.isEmpty == false
    }

    public init(profile: DeveloperProfile, showsEmptyState: Bool = false) {
        self.profile = profile
        self.showsEmptyState = showsEmptyState
    }

    public var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if let headline = nonEmpty(profile.headline) {
                    Text(headline)
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let status = availability {
                    HStack(spacing: AppSpacing.xs) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 8, height: 8)
                        Text(status.title)
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(status.color)
                    }
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(status.color.opacity(0.12), in: Capsule())
                }

                if let currentlyBuilding = nonEmpty(profile.currentlyBuilding) {
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(AppColors.accent)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Currently building")
                                .font(AppTypography.caption.weight(.semibold))
                                .foregroundStyle(AppColors.textSecondary)
                            Text(currentlyBuilding)
                                .font(AppTypography.subheadline)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.secondaryBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.md))
                }

                if !profile.skills.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        sectionTitle("Stack", systemImage: "curlybraces")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), alignment: .leading)], alignment: .leading, spacing: AppSpacing.xs) {
                            ForEach(profile.skills, id: \.self) { skill in
                                Text(skill)
                                    .font(AppTypography.caption.weight(.medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, AppSpacing.xs)
                                    .background(AppColors.secondaryBackground, in: Capsule())
                            }
                        }
                    }
                }

                if !pinnedProjects.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        sectionTitle("Pinned projects", systemImage: "pin.fill")
                        ForEach(pinnedProjects) { project in
                            projectCard(project)
                        }
                    }
                }

                if let location = nonEmpty(profile.location) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(AppColors.textSecondary)
                        Text(location)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                profileLinks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if showsEmptyState {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label("Developer profile", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Add your stack, projects, and links to build your public profile.")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .background(AppColors.secondaryBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.md))
        }
    }

    @ViewBuilder
    private var profileLinks: some View {
        let links = [
            ("Website", "safari", profile.websiteURL),
            ("GitHub", "chevron.left.forwardslash.chevron.right", profile.githubURL),
            ("LinkedIn", "person.crop.rectangle", profile.socialLinks.linkedinURL),
            ("Instagram", "camera", profile.socialLinks.instagramURL),
            ("X", "at", profile.socialLinks.xURL)
        ].compactMap { entry -> (String, String, URL)? in
            guard let value = nonEmpty(entry.2), let url = safeWebURL(value) else { return nil }
            return (entry.0, entry.1, url)
        }

        if !links.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                sectionTitle("Around the web", systemImage: "link")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)],
                    alignment: .leading,
                    spacing: AppSpacing.sm
                ) {
                    ForEach(links, id: \.0) { entry in
                        Link(destination: entry.2) {
                            Label(entry.0, systemImage: entry.1)
                                .font(AppTypography.caption.weight(.semibold))
                                .foregroundStyle(AppColors.accent)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, AppSpacing.sm)
                                .frame(minHeight: 44)
                                .background(AppColors.accent.opacity(0.1), in: Capsule())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityHint("Opens \(entry.0) in a browser")
                    }
                }
            }
        }
    }

    private func projectCard(_ project: DeveloperProject) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.title)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.xs)
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.accent)
                    .accessibilityLabel("Pinned project")
            }

            if !project.summary.isEmpty {
                Text(project.summary)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !project.technologies.isEmpty {
                Text(project.technologies.joined(separator: "  ·  "))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: AppSpacing.md) {
                if let url = safeWebURL(project.repositoryURL) {
                    Link(destination: url) {
                        Label("Repository", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(AppTypography.caption.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Opens this project's source repository")
                }
                if let url = safeWebURL(project.liveURL) {
                    Link(destination: url) {
                        Label("Live demo", systemImage: "arrow.up.right")
                            .font(AppTypography.caption.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Opens this project's live website")
                }
            }
            .foregroundStyle(AppColors.accent)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground, in: RoundedRectangle(cornerRadius: AppCornerRadius.md))
    }

    private var availability: (title: String, color: Color)? {
        switch profile.workAvailability {
        case "open_to_opportunities": ("Open to opportunities", AppColors.statusOnline)
        case "available_for_work": ("Available for work", AppColors.statusOnline)
        case "not_available": ("Not available", AppColors.textSecondary)
        default: nil
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(AppTypography.headline)
            .foregroundStyle(AppColors.textPrimary)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func safeWebURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}
