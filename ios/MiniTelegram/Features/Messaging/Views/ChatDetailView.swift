import SwiftUI

public struct ChatDetailView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: ChatViewModel
    @ObservedObject private var presence = PresenceManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingProfile = false
    @State private var theme: ChatTheme
    @State private var showingThemePicker = false
    @State private var showingNicknameAlert = false
    @State private var nicknameDraft = ""
    /// Bumped when a nickname changes so the header re-reads it
    @State private var nicknameVersion = 0

    public init(conversation: ConversationItem) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
        _theme = State(initialValue: ChatTheme.theme(for: conversation.id))
    }

    public var body: some View {
        // Message list with the composer floating over the bottom of it
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, msg in
                        messageRow(index: index, msg: msg)
                    }
                }
                .padding(.vertical, AppSpacing.sm)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(
                LinearGradient(colors: theme.background, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composer
            }
        }
        .environment(\.chatTheme, theme)
        .navigationBarTitleDisplayMode(.inline)
        // The top bar takes the theme's colours too
        .toolbarBackground(theme.barBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
        .tint(theme.accent)
        // Full-screen chat like Telegram: no tab bar while chatting (it returns on going back)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingThemePicker) {
            ChatThemePickerView(selected: theme) { picked in
                ChatTheme.setTheme(picked, for: viewModel.conversation.id)
                withAnimation(.easeInOut(duration: 0.25)) { theme = picked }
            }
        }
        .alert("Nickname", isPresented: $showingNicknameAlert) {
            TextField(viewModel.conversation.title, text: $nicknameDraft)
            Button("Save") {
                if let userId = viewModel.conversation.recipientUserId {
                    ContactNicknames.set(nicknameDraft, for: userId)
                }
            }
            if let userId = viewModel.conversation.recipientUserId, ContactNicknames.nickname(for: userId) != nil {
                Button("Remove Nickname", role: .destructive) {
                    ContactNicknames.set(nil, for: userId)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only you see this name.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .contactNicknamesChanged)) { _ in
            nicknameVersion += 1
        }
        // The call screen is shown app-wide by MainTabView
        .sheet(isPresented: $showingProfile) {
            if let userId = viewModel.conversation.recipientUserId {
                FriendProfileView(
                    userId: userId,
                    name: viewModel.conversation.title,
                    avatarUrl: viewModel.conversation.avatarUrl
                )
            }
        }
        .task {
            await viewModel.syncMessages()
        }
        .onAppear {
            // Messages for the chat on screen play a soft sound instead of a banner
            MessageAlertManager.shared.activeConversationId = viewModel.conversation.id
        }
        .onDisappear {
            if MessageAlertManager.shared.activeConversationId == viewModel.conversation.id {
                MessageAlertManager.shared.activeConversationId = nil
            }
            RealtimeService.shared.leaveConversation(conversationId: viewModel.conversation.id)
        }
    }

    private var composer: some View {
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
            },
            onSendAttachment: { fileUrl, fileName, mimeType in
                guard let user = appState.currentUser else { return }
                Task {
                    await viewModel.sendAttachment(
                        fileURL: fileUrl,
                        fileName: fileName,
                        mimeType: mimeType,
                        currentUserId: user.id,
                        currentUsername: user.displayName
                    )
                }
            },
            onSendVoiceNote: { fileUrl, duration, waveform in
                guard let user = appState.currentUser else { return }
                Task {
                    await viewModel.sendVoiceNote(
                        fileURL: fileUrl,
                        duration: duration,
                        waveform: waveform,
                        currentUserId: user.id,
                        currentUsername: user.displayName
                    )
                }
            }
        )
        .onChange(of: viewModel.inputText) { _, newText in
            viewModel.handleInputChanged(newText)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // Tap the title to view the other person's profile (1:1 chats)
            Button(action: { showingProfile = true }) {
                HStack(spacing: 8) {
                    AvatarView(
                        name: viewModel.conversation.title,
                        avatarUrl: viewModel.conversation.avatarUrl,
                        size: 32,
                        borderTemplate: viewModel.conversation.borderTemplateEnum
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        AccountDisplayNameView(
                            name: headerTitle,
                            isDeveloper: viewModel.conversation.isRecipientDeveloper,
                            isOwner: viewModel.conversation.isRecipientOwner,
                            nameColorHex: viewModel.conversation.recipientNameColor,
                            font: AppTypography.headline,
                            color: theme.foreground,
                            badgeSize: 14
                        )

                        headerSubtitle
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.conversation.recipientUserId == nil)
        }

        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button(action: {
                Task {
                    await CallManager.shared.startCall(
                        conversationId: viewModel.conversation.id,
                        title: viewModel.conversation.title,
                        callType: .audio
                    )
                }
            }) {
                Image(systemName: "phone")
                    .font(.system(size: 17))
                    .foregroundColor(theme.accent)
            }

            Button(action: {
                Task {
                    await CallManager.shared.startCall(
                        conversationId: viewModel.conversation.id,
                        title: viewModel.conversation.title,
                        callType: .video
                    )
                }
            }) {
                Image(systemName: "video")
                    .font(.system(size: 17))
                    .foregroundColor(theme.accent)
            }

            if viewModel.conversation.type == "group" {
                NavigationLink(destination: GroupInfoView(conversation: viewModel.conversation)) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundColor(theme.accent)
                }
            }

            Menu {
                Button {
                    showingThemePicker = true
                } label: {
                    Label("Chat Theme", systemImage: "paintpalette")
                }
                if let userId = viewModel.conversation.recipientUserId {
                    Button {
                        nicknameDraft = ContactNicknames.nickname(for: userId) ?? ""
                        showingNicknameAlert = true
                    } label: {
                        Label("Set Nickname", systemImage: "pencil")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 17))
                    .foregroundColor(theme.accent)
            }
        }
}

    /// One message: date divider (when the day changes), the bubble, and "Seen" under my latest message.
    @ViewBuilder
    private func messageRow(index: Int, msg: ChatMessage) -> some View {
        // Date divider
        if shouldShowDateDivider(at: index) {
            DateDividerView(date: msg.timestamp, theme: theme)
        }

        MessageBubbleView(
            message: msg,
            theme: theme,
            showSenderName: viewModel.conversation.type == "group",
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

        // "Seen" under my latest message once the other person has read it
        if msg.id == lastOutgoingMessageId && msg.status == .read {
            // Their little photo, like Messenger's "seen" indicator
            HStack(spacing: 4) {
                Spacer()
                Text("Seen")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(theme.accent)
                AvatarView(
                    name: viewModel.conversation.title,
                    avatarUrl: viewModel.conversation.avatarUrl,
                    size: 16
                )
            }
            .padding(.trailing, AppSpacing.md)
            .padding(.top, -2)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var headerSubtitle: some View {
        if viewModel.isPeerTyping {
            Text(L("chat_typing_single", viewModel.peerTypingName))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.accent)
        } else if viewModel.conversation.type == "group" {
            Text("\(viewModel.conversation.memberCount) members")
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryForeground)
        } else if isPeerOnline {
            HStack(spacing: 4) {
                Circle()
                    .fill(AppColors.statusOnline)
                    .frame(width: 7, height: 7)
                Text(L("chat_online"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.statusOnline)
            }
        } else if let lastSeenText = peerLastSeenText, !lastSeenText.isEmpty {
            Text(lastSeenText)
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryForeground)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                Text(L("chat_e2ee_badge"))
                    .font(.system(size: 10))
            }
            .foregroundColor(theme.secondaryForeground)
        }
    }

    private var isPeerOnline: Bool {
        presence.isOnline(viewModel.conversation.recipientUserId, fallback: viewModel.conversation.isOnline)
    }

    private var peerLastSeenText: String? {
        let text = presence.statusText(for: viewModel.conversation.recipientUserId)
        if !text.isEmpty && text != "Online" {
            return text
        }
        if let date = viewModel.conversation.lastSeen {
            return presence.formatLastSeen(date)
        }
        return nil
    }

    /// Nickname if you set one, otherwise the chat's name
    private var headerTitle: String {
        _ = nicknameVersion
        return ContactNicknames.displayName(userId: viewModel.conversation.recipientUserId, fallback: viewModel.conversation.title)
    }

    private var lastOutgoingMessageId: String? {
        viewModel.messages.last { $0.isOutgoing }?.id
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
    public var theme: ChatTheme = .classic

    public var body: some View {
        Text(formattedDate(date))
            .font(AppTypography.caption.weight(.semibold))
            .foregroundColor(theme.surfaceText.opacity(0.65))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 5)
            .background(theme.surface.opacity(0.85), in: Capsule())
            .overlay(Capsule().stroke(theme.border, lineWidth: 1))
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
