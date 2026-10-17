import SwiftUI

public struct ConversationListView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ConversationsViewModel()
    @State private var selectedConversation: ConversationItem?

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
                }
            } else {
                // Conversation Rows
                List(viewModel.conversations) { conv in
                    NavigationLink(destination: ChatDetailView(conversation: conv)) {
                        ConversationRowView(conversation: conv)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.refreshConversations()
                }
            }
        }
        .navigationTitle(L("chats_title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    viewModel.isPresentingNewChat = true
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .sheet(isPresented: $viewModel.isPresentingNewChat) {
            NewConversationSheet(
                viewModel: viewModel,
                selectedConversation: $selectedConversation
            )
        }
        .navigationDestination(item: $selectedConversation) { conv in
            ChatDetailView(conversation: conv)
        }
        .task {
            await viewModel.refreshConversations()
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

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Avatar with Online Badge
            ZStack(alignment: .bottomTrailing) {
                AvatarView(name: conversation.title, size: 52)

                if conversation.isOnline {
                    Circle()
                        .fill(AppColors.statusOnline)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.title)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

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
