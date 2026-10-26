import SwiftUI
import Combine

/// Full-screen story player: progress bars, tap right/left to go forward/back, hold to pause,
/// swipe down to close. Supports replying to stories, luxury reactions, and sharing.
struct StoryViewerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StoriesStore.shared

    @State private var groups: [UserStories]
    @State private var groupIndex: Int
    @State private var storyIndex: Int
    @State private var progress: Double = 0
    @State private var image: UIImage?
    @State private var loadFailed = false
    @State private var isHolding = false
    @State private var dragOffset: CGFloat = 0
    @State private var showingViewers = false
    @State private var showingReactions = false
    @State private var showingShareSheet = false
    @State private var confirmingDelete = false

    // Story reply and reaction states
    @State private var currentReactions: [StoriesStore.ReactionSummary] = []
    @State private var replyText: String = ""
    @FocusState private var isReplyFocused: Bool
    @State private var floatingReaction: StoryReactionOption?
    @State private var floatingReactionOffset: CGFloat = 0
    @State private var floatingReactionOpacity: Double = 0
    @State private var toastMessage: String?
    @State private var isSendingReply = false

    private static let storyDuration: Double = 5
    private static let tick: Double = 0.05
    private let timer = Timer.publish(every: tick, on: .main, in: .common).autoconnect()

    init(groups: [UserStories], startUserId: String) {
        let playable = groups.filter { !$0.stories.isEmpty }
        let start = playable.firstIndex { $0.user_id == startUserId } ?? 0
        _groups = State(initialValue: playable)
        _groupIndex = State(initialValue: start)
        _storyIndex = State(initialValue: playable.indices.contains(start) && !playable[start].is_me
            ? playable[start].firstUnseenIndex : 0)
    }

    private var group: UserStories? { groups.indices.contains(groupIndex) ? groups[groupIndex] : nil }
    private var story: StoryItem? {
        guard let group, group.stories.indices.contains(storyIndex) else { return nil }
        return group.stories[storyIndex]
    }

    private var isPaused: Bool {
        isHolding || showingViewers || showingReactions || showingShareSheet || confirmingDelete ||
        image == nil || dragOffset > 0 || isReplyFocused || !replyText.isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let group, let story {
                media
                    .ignoresSafeArea(edges: .bottom)

                tapZones

                VStack(spacing: 8) {
                    progressBars(count: group.stories.count)
                    header(group: group, story: story)
                    Spacer()
                    footer(group: group, story: story)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .opacity(isHolding ? 0 : 1)
                .animation(.easeInOut(duration: 0.15), value: isHolding)

                // Floating Reaction Animation
                if let reaction = floatingReaction {
                    Image(systemName: reaction.systemImage)
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(reaction.tintColor)
                        .shadow(color: reaction.tintColor.opacity(0.6), radius: 12)
                        .offset(y: floatingReactionOffset)
                        .opacity(floatingReactionOpacity)
                        .allowsHitTesting(false)
                }

                // Toast Feedback
                if let toastMessage {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(AppColors.accent)
                            Text(toastMessage)
                                .font(AppTypography.caption.weight(.semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .padding(.bottom, 110)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toastMessage)
                }
            }
        }
        .offset(y: dragOffset)
        .scaleEffect(1 - min(dragOffset, 300) / 3000)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if !isReplyFocused {
                        dragOffset = max(0, value.translation.height)
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                    }
                }
        )
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onReceive(timer) { _ in
            guard !isPaused else { return }
            progress += Self.tick / Self.storyDuration
            if progress >= 1 { goForward() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OurChat.realtimeStoryReaction"))) { notification in
            guard let payload = notification.object as? [String: Any],
                  let eventStoryId = payload["story_id"] as? String,
                  let currentStory = story,
                  eventStoryId == currentStory.id,
                  let reactionKey = payload["reaction"] as? String else {
                return
            }

            // Realtime reaction motion particle visible to all viewers
            if let option = StoryReactionOption(rawValue: reactionKey) {
                floatingReaction = option
                floatingReactionOffset = 50
                floatingReactionOpacity = 1

                withAnimation(.easeOut(duration: 0.8)) {
                    floatingReactionOffset = -180
                    floatingReactionOpacity = 0
                }
            }

            if let idx = currentReactions.firstIndex(where: { $0.reaction == reactionKey }) {
                let prev = currentReactions[idx]
                currentReactions[idx] = StoriesStore.ReactionSummary(reaction: prev.reaction, count: prev.count + 1)
            } else {
                currentReactions.append(StoriesStore.ReactionSummary(reaction: reactionKey, count: 1))
            }
        }
        .task(id: story?.id) { await loadCurrent() }
        .sheet(isPresented: $showingViewers) {
            if let story { StoryViewersSheet(storyId: story.id) }
        }
        .sheet(isPresented: $showingReactions) {
            if let story { StoryReactionsSummarySheet(storyId: story.id) }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let img = image {
                ActivityShareSheet(items: [img, "Shared via Mini Telegram"])
            }
        }
        .confirmationDialog("Delete this story?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Story", role: .destructive) { Task { await deleteCurrent() } }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { if groups.isEmpty { dismiss() } }
    }

    // MARK: - Media & Tap Zones

    @ViewBuilder
    private var media: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        } else if loadFailed {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30))
                Text("Couldn't load this story")
                    .font(AppTypography.subheadline)
                Button("Try Again") { Task { await loadCurrent() } }
                    .font(AppTypography.subheadline.weight(.semibold))
            }
            .foregroundColor(.white.opacity(0.85))
        } else {
            ProgressView().tint(.white)
        }
    }

    /// Left third goes back, the rest goes forward; holding anywhere pauses.
    private var tapZones: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width * 0.3)
                    .onTapGesture {
                        if isReplyFocused {
                            isReplyFocused = false
                        } else {
                            goBack()
                        }
                    }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isReplyFocused {
                            isReplyFocused = false
                        } else {
                            goForward()
                        }
                    }
            }
            .onLongPressGesture(minimumDuration: 0.25, maximumDistance: 30, perform: {}) { pressing in
                if !isReplyFocused {
                    isHolding = pressing
                }
            }
        }
    }

    private func progressBars(count: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.3))
                        Capsule().fill(Color.white)
                            .frame(width: geo.size.width * fill(for: index))
                    }
                }
                .frame(height: 2.5)
            }
        }
    }

    private func fill(for index: Int) -> CGFloat {
        if index < storyIndex { return 1 }
        if index > storyIndex { return 0 }
        return CGFloat(min(max(progress, 0), 1))
    }

    // MARK: - Header

    private func header(group: UserStories, story: StoryItem) -> some View {
        HStack(spacing: 10) {
            AvatarView(
                name: group.display_name,
                avatarUrl: group.avatar_url,
                size: 36,
                borderTemplate: group.borderTemplateEnum
            )

            VStack(alignment: .leading, spacing: 2) {
                AccountDisplayNameView(
                    name: group.is_me ? "My Story" : ContactNicknames.displayName(userId: group.user_id, fallback: group.display_name),
                    isDeveloper: group.isDeveloper,
                    isOwner: group.isAppOwner,
                    nameColorHex: group.name_color,
                    font: AppTypography.subheadline.weight(.semibold),
                    color: .white,
                    badgeSize: 15
                )

                Text(StoryDates.relative(story.created_at))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white.opacity(0.72))
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    showingShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Share Story")

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close")
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 4)
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(group: UserStories, story: StoryItem) -> some View {
        VStack(spacing: 10) {
            if let caption = story.caption, !caption.isEmpty {
                Text(caption)
                    .font(AppTypography.subheadline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }

            // Public Reaction Counter Pill (Visible to everyone)
            if !currentReactions.isEmpty {
                Button {
                    showingReactions = true
                } label: {
                    HStack(spacing: 8) {
                        ForEach(currentReactions.prefix(4), id: \.reaction) { item in
                            if let option = StoryReactionOption(rawValue: item.reaction) {
                                HStack(spacing: 3) {
                                    Image(systemName: option.systemImage)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(option.tintColor)
                                    Text("\(item.count)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View all reactions")
            }

            if group.is_me {
                // Own Story Controls
                HStack(spacing: 10) {
                    Button { showingViewers = true } label: {
                        Label("\(story.view_count ?? 0) \(story.view_count == 1 ? "view" : "views")", systemImage: "eye.fill")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button { showingReactions = true } label: {
                        Label("Reactions", systemImage: "heart.fill")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Spacer()

                    Button { confirmingDelete = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Delete story")
                }
            } else {
                // Friend Story: Reactions Bar & Reply Field
                VStack(spacing: 8) {
                    // Quick Luxury Reactions
                    HStack(spacing: 12) {
                        ForEach(StoryReactionOption.allCases) { reaction in
                            Button {
                                sendReaction(reaction, storyId: story.id)
                            } label: {
                                Image(systemName: reaction.systemImage)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(reaction.tintColor)
                                    .frame(width: 36, height: 36)
                                    .background(Color.black.opacity(0.35), in: Circle())
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                    // Reply Input Field
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.5))

                            TextField("Reply to \(group.display_name)...", text: $replyText)
                                .font(AppTypography.subheadline)
                                .foregroundColor(.white)
                                .tint(AppColors.accent)
                                .focused($isReplyFocused)
                                .submitLabel(.send)
                                .onSubmit {
                                    sendReply(storyId: story.id)
                                }

                            if !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    sendReply(storyId: story.id)
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(AppColors.accent)
                                }
                                .disabled(isSendingReply)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )

                        Button {
                            showingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.14), lineWidth: 1)
                                )
                        }
                        .accessibilityLabel("Share Story")
                    }
                }
            }
        }
        .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Actions

    private func sendReaction(_ reaction: StoryReactionOption, storyId: String) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        floatingReaction = reaction
        floatingReactionOffset = 50
        floatingReactionOpacity = 1

        withAnimation(.easeOut(duration: 0.8)) {
            floatingReactionOffset = -180
            floatingReactionOpacity = 0
        }

        // Optimistic local update
        if let idx = currentReactions.firstIndex(where: { $0.reaction == reaction.rawValue }) {
            let prev = currentReactions[idx]
            currentReactions[idx] = StoriesStore.ReactionSummary(reaction: prev.reaction, count: prev.count + 1)
        } else {
            currentReactions.append(StoriesStore.ReactionSummary(reaction: reaction.rawValue, count: 1))
        }

        Task {
            let success = await store.react(storyId: storyId, reaction: reaction.rawValue)
            if success {
                showToast("Reaction sent")
            }
        }
    }

    private func sendReply(storyId: String) {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingReply else { return }

        isSendingReply = true
        isReplyFocused = false

        Task {
            let success = await store.reply(storyId: storyId, text: text)
            isSendingReply = false
            if success {
                replyText = ""
                showToast("Reply sent to chat")
                NotificationCenter.default.post(name: .conversationsChanged, object: nil)
            } else {
                showToast("Couldn't send reply")
            }
        }
    }

    private func showToast(_ msg: String) {
        toastMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toastMessage == msg {
                withAnimation { toastMessage = nil }
            }
        }
    }

    // MARK: - Navigation

    private func goForward() {
        guard let group else { return dismiss() }
        if storyIndex < group.stories.count - 1 {
            storyIndex += 1
        } else if groupIndex < groups.count - 1 {
            groupIndex += 1
            storyIndex = groups[groupIndex].is_me ? 0 : groups[groupIndex].firstUnseenIndex
        } else {
            dismiss()
        }
        progress = 0
    }

    private func goBack() {
        if storyIndex > 0 {
            storyIndex -= 1
        } else if groupIndex > 0 {
            groupIndex -= 1
            storyIndex = 0
        }
        progress = 0
    }

    private func loadCurrent() async {
        guard let group, let story else { return }
        image = nil
        loadFailed = false
        progress = 0
        currentReactions = story.reactions_summary ?? []
        Task {
            let fresh = await store.reactions(storyId: story.id)
            if !Task.isCancelled {
                currentReactions = fresh
            }
        }
        do {
            let data = try await AttachmentManager.shared.downloadAndDecrypt(attachment: story.attachment)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) { image = UIImage(data: data) }
            if image == nil { loadFailed = true }
            if !group.is_me { store.markViewed(userId: group.user_id, storyId: story.id) }
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    private func deleteCurrent() async {
        guard let story else { return }
        await store.delete(storyId: story.id)
        groups[groupIndex].stories.removeAll { $0.id == story.id }
        if groups[groupIndex].stories.isEmpty {
            dismiss()
        } else {
            storyIndex = min(storyIndex, groups[groupIndex].stories.count - 1)
            progress = 0
        }
    }
}

// MARK: - Luxury Story Reaction Options (No Emojis)

enum StoryReactionOption: String, CaseIterable, Identifiable {
    case heart
    case flame
    case star
    case thumbsUp
    case sparkles

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .heart: return "heart.fill"
        case .flame: return "flame.fill"
        case .star: return "star.fill"
        case .thumbsUp: return "hand.thumbsup.fill"
        case .sparkles: return "sparkles"
        }
    }

    var tintColor: Color {
        switch self {
        case .heart: return Color(red: 0.95, green: 0.32, blue: 0.38)
        case .flame: return Color(red: 0.98, green: 0.60, blue: 0.22)
        case .star: return Color(red: 0.96, green: 0.78, blue: 0.28)
        case .thumbsUp: return Color(red: 0.45, green: 0.72, blue: 0.98)
        case .sparkles: return Color(red: 0.88, green: 0.82, blue: 0.98)
        }
    }
}

// MARK: - Activity Share Sheet

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Story Viewers Sheet

private struct StoryViewersSheet: View {
    let storyId: String
    @Environment(\.dismiss) private var dismiss
    @State private var viewers: [StoriesStore.Viewer] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if viewers.isEmpty {
                    EmptyStateView(icon: "eye.slash", title: "No views yet", description: "Friends who see your story will show up here.")
                } else {
                    List(viewers) { viewer in
                        HStack(spacing: 12) {
                            AvatarView(name: viewer.display_name, avatarUrl: viewer.avatar_url, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ContactNicknames.displayName(userId: viewer.user_id, fallback: viewer.display_name))
                                    .font(AppTypography.headline)
                                Text(StoryDates.relative(viewer.viewed_at))
                                    .font(AppTypography.caption)
                                    .foregroundColor(AppColors.textSecondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Viewers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task {
                viewers = await StoriesStore.shared.viewers(storyId: storyId)
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Story Reactions Summary Sheet

private struct StoryReactionsSummarySheet: View {
    let storyId: String
    @Environment(\.dismiss) private var dismiss
    @State private var summaries: [StoriesStore.ReactionSummary] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if summaries.isEmpty {
                    EmptyStateView(icon: "heart.slash", title: "No reactions yet", description: "Reactions from friends will appear here.")
                } else {
                    List(summaries, id: \.reaction) { item in
                        HStack(spacing: 14) {
                            if let reaction = StoryReactionOption(rawValue: item.reaction) {
                                Image(systemName: reaction.systemImage)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(reaction.tintColor)
                                    .frame(width: 38, height: 38)
                                    .background(reaction.tintColor.opacity(0.12), in: Circle())
                            } else {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.accent)
                                    .frame(width: 38, height: 38)
                                    .background(AppColors.accent.opacity(0.12), in: Circle())
                            }

                            Text(item.reaction.capitalized)
                                .font(AppTypography.body.weight(.medium))

                            Spacer()

                            Text("\(item.count)")
                                .font(AppTypography.headline)
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .task {
                summaries = await StoriesStore.shared.reactions(storyId: storyId)
                isLoading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}
