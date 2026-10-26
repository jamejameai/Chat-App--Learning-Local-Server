import SwiftUI

public struct ConversationListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ConversationsViewModel()
    @State private var selectedConversation: ConversationItem?
    @State private var profileConversation: ConversationItem?
    @State private var storyViewerStart: StoryViewerStart?
    @State private var isPresentingNewGroup = false
    @State private var wantsNewGroupAfterSheet = false
    @State private var createdGroup: ConversationItem?
    @ObservedObject private var stories = StoriesStore.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColors.textTertiary)

                TextField(L("chats_search_placeholder"), text: $viewModel.searchQuery)
                    .font(AppTypography.body)

                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 8)
            .background(AppColors.surface)
            .cornerRadius(AppCornerRadius.md)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)

            // Content
            if !viewModel.searchQuery.isEmpty {
                // Search Results
                if viewModel.searchResults.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Messages Found",
                        description: "No local messages matched your search query."
                    )
                } else {
                    List(viewModel.searchResults) { msg in
                        NavigationLink(destination: ChatDetailView(
                            conversation: viewModel.conversations.first(where: { $0.id == msg.conversationId }) ??
                                ConversationItem(id: msg.conversationId, title: "Chat")
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(msg.senderName)
                                        .font(AppTypography.headline)
                                        .foregroundColor(AppColors.textPrimary)
                                    Spacer()
                                    Text(formattedTime(msg.timestamp))
                                        .font(AppTypography.caption)
                                        .foregroundColor(AppColors.textTertiary)
                                }
                                Text(msg.text)
                                    .font(AppTypography.body)
                                    .foregroundColor(AppColors.textSecondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            } else if viewModel.conversations.isEmpty && !viewModel.isLoading {
                // Empty state with quick start button
                VStack(spacing: AppSpacing.md) {
                    StoriesBarView()
                    EmptyStateView(
                        icon: "bubble.left.and.bubble.right",
                        title: L("chats_empty_title"),
                        description: L("chats_empty_description")
                    )

                    PrimaryButton(
                        title: "Start Conversation",
                        icon: "square.and.pencil"
                    ) {
                        viewModel.isPresentingNewChat = true
                    }
                    .frame(maxWidth: 240)

                    Button {
                        isPresentingNewGroup = true
                    } label: {
                        Label("New Group", systemImage: "person.3.fill")
                            .font(AppTypography.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.accent)
                    }
                }
            } else {
                // Conversation Rows, with the stories scrolling along at the top
                List {
                    StoriesBarView()
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)

                    ForEach(viewModel.conversations) { conv in
                        NavigationLink(destination: ChatDetailView(conversation: conv)) {
                            ConversationRowView(conversation: conv)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .contextMenu {
                            if let userId = conv.recipientUserId, stories.stories(for: userId) != nil {
                                Button {
                                    storyViewerStart = StoryViewerStart(id: userId)
                                } label: {
                                    Label("View Story", systemImage: "circle.dashed.inset.filled")
                                }
                            }
                            // Long-press a 1:1 chat to see the person's profile
                            if conv.recipientUserId != nil {
                                Button {
                                    profileConversation = conv
                                } label: {
                                    Label("View Profile", systemImage: "person.crop.circle")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    async let chats: Void = viewModel.refreshConversations()
                    async let feed: Void = stories.load()
                    _ = await (chats, feed)
                }
            }
        }
        .navigationTitle(L("chats_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: {
                    isPresentingNewGroup = true
                }) {
                    Image(systemName: "person.2.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
                .accessibilityLabel("New Group")

                Button(action: {
                    viewModel.isPresentingNewChat = true
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
                .accessibilityLabel("New Message")
            }
        }
        .sheet(isPresented: $viewModel.isPresentingNewChat, onDismiss: {
            // "New Group" inside the sheet: open the group sheet once this one has gone
            if wantsNewGroupAfterSheet {
                wantsNewGroupAfterSheet = false
                isPresentingNewGroup = true
            }
        }) {
            NewConversationSheet(
                viewModel: viewModel,
                selectedConversation: $selectedConversation,
                onNewGroup: {
                    wantsNewGroupAfterSheet = true
                    viewModel.isPresentingNewChat = false
                }
            )
        }
        .sheet(isPresented: $isPresentingNewGroup, onDismiss: {
            // Open the new group once the sheet has gone
            if let group = createdGroup {
                createdGroup = nil
                selectedConversation = group
            }
        }) {
            CreateGroupSheet { group in
                createdGroup = group
                viewModel.loadLocalConversations()
                Task { await viewModel.refreshConversations() }
            }
        }
        .navigationDestination(item: $selectedConversation) { conv in
            ChatDetailView(conversation: conv)
        }
        .task {
            stories.refresh()
            await viewModel.refreshConversations()
        }
        .fullScreenCover(item: $storyViewerStart) { start in
            StoryViewerView(groups: stories.feed, startUserId: start.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openConversationRequested)) { _ in
            openPendingConversation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .contactNicknamesChanged)) { _ in
            viewModel.loadLocalConversations() // re-render rows with the new nickname
        }
        .onAppear {
            // A notification tap that launched the app arrives before this screen exists
            openPendingConversation()
        }
        .sheet(item: $profileConversation) { conv in
            if let userId = conv.recipientUserId {
                FriendProfileView(userId: userId, name: conv.title, avatarUrl: conv.avatarUrl)
            }
        }
    }

    /// Opens the chat of a tapped message notification.
    private func openPendingConversation() {
        guard let conversationId = MessageAlertManager.shared.pendingConversationId else { return }
        MessageAlertManager.shared.pendingConversationId = nil
        if let conv = LocalDatabaseManager.shared.getConversation(byId: conversationId) {
            selectedConversation = conv
        } else {
            Task {
                await viewModel.refreshConversations()
                selectedConversation = viewModel.conversations.first { $0.id == conversationId }
            }
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// Conversation Row Component
public struct ConversationRowView: View {
    public let conversation: ConversationItem
    @ObservedObject private var stories = StoriesStore.shared
    @ObservedObject private var presence = PresenceManager.shared

    private var isOnline: Bool {
        presence.isOnline(conversation.recipientUserId, fallback: conversation.isOnline)
    }

    public init(conversation: ConversationItem) {
        self.conversation = conversation
    }

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Avatar with Online Badge
            ZStack(alignment: .bottomTrailing) {
                // Coloured ring when this person has a story you haven't seen
                StoryRingAvatar(
                    name: conversation.title,
                    avatarUrl: conversation.avatarUrl,
                    size: 50,
                    ring: stories.ringState(for: conversation.recipientUserId),
                    borderTemplate: conversation.borderTemplateEnum
                )

                if isOnline {
                    Circle()
                        .fill(AppColors.statusOnline)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    AccountDisplayNameView(
                        name: ContactNicknames.displayName(userId: conversation.recipientUserId, fallback: conversation.title),
                        isDeveloper: conversation.isRecipientDeveloper,
                        isOwner: conversation.isRecipientOwner,
                        nameColorHex: conversation.recipientNameColor,
                        font: AppTypography.headline,
                        color: AppColors.textPrimary
                    )

                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textTertiary)
                    }

                    Spacer()

                    if let timestamp = conversation.lastMessageTimestamp {
                        Text(formatSnippetTime(timestamp))
                            .font(AppTypography.caption)
                            .foregroundColor(conversation.unreadCount > 0 ? AppColors.accent : AppColors.textTertiary)
                    }
                }

                HStack {
                    Text(conversation.lastMessageText ?? "No messages yet")
                        .font(AppTypography.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(AppTypography.caption.weight(.bold))
                            .foregroundColor(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppColors.accent)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSnippetTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d/yy"
            return formatter.string(from: date)
        }
    }
}
