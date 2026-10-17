import SwiftUI

public struct ChatDetailView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    public init(conversation: ConversationItem) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Message List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, msg in
                            // Date divider
                            if shouldShowDateDivider(at: index) {
                                DateDividerView(date: msg.timestamp)
                            }

                            MessageBubbleView(
                                message: msg,
                                onReply: { target in
                                    viewModel.replyingToMessage = target
                                },
                                onReact: { target, emoji in
                                    if let userId = appState.currentUser?.id {
                                        viewModel.toggleReaction(message: target, emoji: emoji, currentUserId: userId)
                                    }
                                }
                            )
                            .id(msg.id)
                            .onAppear {
                                if !msg.isOutgoing && msg.status != .read {
                                    viewModel.markDeliveredOrRead(message: msg, status: .read)
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.sm)
                }
                .background(AppColors.background)
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Composer
            MessageComposerView(
                text: $viewModel.inputText,
                replyingTo: viewModel.replyingToMessage,
                onCancelReply: {
                    viewModel.replyingToMessage = nil
                },
                onSend: {
                    guard let user = appState.currentUser else { return }
                    Task {
                        await viewModel.sendMessage(currentUserId: user.id, currentUsername: user.displayName)
                    }
                }
            )
            .onChange(of: viewModel.inputText) { newText in
                viewModel.handleInputChanged(newText)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(viewModel.conversation.title)
                        .font(AppTypography.headline)
                        .foregroundColor(AppColors.textPrimary)

                    if viewModel.isPeerTyping {
                        Text(L("chat_typing_single", viewModel.peerTypingName))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.accent)
                    } else if viewModel.conversation.isOnline {
                        Text(L("chat_online"))
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.statusOnline)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text(L("chat_e2ee_badge"))
                                .font(.system(size: 10))
                        }
                        .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
        }
        .task {
            await viewModel.syncMessages()
        }
    }

    private func shouldShowDateDivider(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = viewModel.messages[index - 1].timestamp
        let curr = viewModel.messages[index].timestamp
        return !Calendar.current.isDate(prev, inSameDayAs: curr)
    }
}

public struct DateDividerView: View {
    public let date: Date

    public var body: some View {
        Text(formattedDate(date))
            .font(AppTypography.caption.weight(.medium))
            .foregroundColor(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 4)
            .background(AppColors.surface)
            .cornerRadius(AppCornerRadius.full)
            .padding(.vertical, AppSpacing.xs)
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}
