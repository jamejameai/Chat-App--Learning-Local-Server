import SwiftUI

public struct MessageBubbleView: View {
    public let message: ChatMessage
    public let onReply: (ChatMessage) -> Void
    public let onReact: (ChatMessage, String) -> Void
    /// Colours of this chat's theme
    public var theme: ChatTheme
    /// Group chats show who wrote each message; 1:1 chats don't need it
    public var showSenderName: Bool

    private let availableReactions: [(id: String, name: String, icon: String, color: Color)] = [
        ("heart", "Heart", "heart.fill", Color(red: 1.0, green: 0.23, blue: 0.19)),
        ("thumbsUp", "Like", "hand.thumbsup.fill", Color(red: 0.0, green: 0.48, blue: 1.0)),
        ("flame", "Fire", "flame.fill", Color(red: 1.0, green: 0.58, blue: 0.0)),
        ("star", "Star", "star.fill", Color(red: 1.0, green: 0.84, blue: 0.0)),
        ("sparkles", "Sparkles", "sparkles", Color(red: 0.69, green: 0.32, blue: 0.87))
    ]

    public init(
        message: ChatMessage,
        theme: ChatTheme = .classic,
        showSenderName: Bool = false,
        onReply: @escaping (ChatMessage) -> Void,
        onReact: @escaping (ChatMessage, String) -> Void
    ) {
        self.message = message
        self.theme = theme
        self.showSenderName = showSenderName
        self.onReply = onReply
        self.onReact = onReact
    }

    private var textColor: Color { message.isOutgoing ? theme.outgoingText : theme.incomingText }
    private var metaColor: Color { message.isOutgoing ? theme.outgoingMeta : theme.incomingMeta }
    /// Photo / file / voice with no caption: the time floats on the media instead of after text
    private var isMediaOnly: Bool { message.text.isEmpty && (message.attachment != nil || message.voiceNote != nil) }

    /// Invisible copy of the footer appended to the text, so the time/ticks overlay never covers words
    /// and the bubble stays exactly as wide as the message (Telegram-style).
    private var footerReservation: String {
        "\u{2002}\u{2002}" + formattedTime(message.timestamp) + (message.isOutgoing ? "\u{2002}\u{2002}\u{2002}" : "")
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.xs) {
            if message.isOutgoing {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 2) {
                // Main Bubble
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    // Sender Name (for incoming messages)
                    if showSenderName && !message.isOutgoing && !message.senderName.isEmpty {
                        let isDev = message.senderRole == "owner" || message.senderUserId == "jame.kh" || message.senderName.lowercased().contains("jame")
                        let isOwner = message.senderRole == "owner" || message.senderUserId == "jame.kh" || message.senderName.lowercased().contains("jame")
                        AccountDisplayNameView(
                            name: ContactNicknames.displayName(userId: message.senderUserId, fallback: message.senderName),
                            isDeveloper: isDev,
                            isOwner: isOwner,
                            nameColorHex: message.senderNameColor,
                            font: .system(size: 13, weight: .semibold),
                            color: theme.accent,
                            badgeSize: 13
                        )
                    }

                    // Quoted Reply Preview
                    if let replyText = message.replyPreview {
                        HStack(spacing: AppSpacing.xs) {
                            Rectangle()
                                .fill(message.isOutgoing ? theme.outgoingText.opacity(0.8) : theme.accent)
                                .frame(width: 3)

                            Text(replyText)
                                .font(AppTypography.caption)
                                .lineLimit(2)
                                .foregroundColor(message.isOutgoing ? theme.outgoingText.opacity(0.9) : theme.incomingMeta)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(message.isOutgoing ? Color.white.opacity(0.15) : theme.accent.opacity(0.1))
                        .cornerRadius(AppCornerRadius.sm)
                        .fixedSize(horizontal: false, vertical: true) // the quote bar must not stretch the bubble
                    }

                    // Voice Note View
                    if let voiceNote = message.voiceNote {
                        VoiceMessageBubbleView(
                            messageId: message.id,
                            isOutgoing: message.isOutgoing,
                            voiceNote: voiceNote,
                            attachment: message.attachment
                        )
                    } else if let attachment = message.attachment {
                        AttachmentBubbleView(
                            attachment: attachment,
                            isOutgoing: message.isOutgoing
                        )
                    }

                    // Message text, with room reserved at the end for the time
                    if !message.text.isEmpty {
                        (Text(message.text).foregroundColor(textColor)
                         + Text(footerReservation).font(.system(size: 11)).foregroundColor(.clear))
                            .font(AppTypography.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, isMediaOnly && message.voiceNote != nil ? 14 : 0)
                // Time + ticks in the bubble's corner (on a dark pill over photos)
                .overlay(alignment: .bottomTrailing) {
                    footer
                        .padding(isMediaOnly && message.voiceNote == nil ? 6 : 0)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 7)
                .background(bubbleBackground)
                .clipShape(BubbleShape(isOutgoing: message.isOutgoing))
                .shadow(color: Color.black.opacity(theme.isDark ? 0 : 0.06), radius: 1.5, y: 1)

                // Reaction Ribbon
                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions) { reaction in
                            let matching = availableReactions.first { $0.id == reaction.emoji }
                            HStack(spacing: 3) {
                                if let icon = matching?.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(matching?.color ?? theme.accent)
                                } else {
                                    Image(systemName: "heart.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(theme.accent)
                                }
                                if reaction.count > 1 {
                                    Text("\(reaction.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(theme.surfaceText)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(theme.surface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(theme.border, lineWidth: 1)
                            )
                            .onTapGesture {
                                onReact(message, reaction.emoji)
                            }
                        }
                    }
                    .padding(.top, -4)
                    .padding(.horizontal, 6)
                }
            }
            .contextMenu {
                // Quick Reactions
                Section {
                    ForEach(availableReactions, id: \.id) { r in
                        Button(action: {
                            onReact(message, r.id)
                        }) {
                            Label(r.name, systemImage: r.icon)
                        }
                    }
                }

                // Actions
                Button(action: {
                    onReply(message)
                }) {
                    Label(L("chat_replying_to", ""), systemImage: "arrowshape.turn.up.left")
                }

                Button(action: {
                    UIPasteboard.general.string = message.text
                }) {
                    Label(L("action_copy"), systemImage: "doc.on.doc")
                }
            }

            if !message.isOutgoing {
                Spacer(minLength: 48)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack(spacing: 3) {
            Text(formattedTime(message.timestamp))
                .font(.system(size: 11))
                .monospacedDigit()
            if message.isOutgoing {
                statusIcon(message.status)
            }
        }
        .foregroundColor(isMediaOnly && message.voiceNote == nil ? .white : metaColor)
        .padding(.horizontal, isMediaOnly && message.voiceNote == nil ? 6 : 0)
        .padding(.vertical, isMediaOnly && message.voiceNote == nil ? 2 : 0)
        .background(isMediaOnly && message.voiceNote == nil ? Color.black.opacity(0.45) : .clear)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isOutgoing {
            LinearGradient(
                colors: theme.outgoing,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            theme.incoming
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: MessageDeliveryStatus) -> some View {
        switch status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 10))
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
        case .delivered:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 9, weight: .semibold))
        case .read:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(theme.outgoingText)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(AppColors.statusError)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// Custom Bubble Shape with Chat Tail
public struct BubbleShape: Shape {
    public let isOutgoing: Bool

    public func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let smallRadius: CGFloat = 4

        return Path { path in
            let topLeft = radius
            let topRight = radius
            let bottomLeft = isOutgoing ? radius : smallRadius
            let bottomRight = isOutgoing ? smallRadius : radius

            path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
                radius: topRight,
                startAngle: Angle(degrees: -90),
                endAngle: Angle(degrees: 0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
            path.addArc(
                center: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
                radius: bottomRight,
                startAngle: Angle(degrees: 0),
                endAngle: Angle(degrees: 90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
                radius: bottomLeft,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 180),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
            path.addArc(
                center: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
                radius: topLeft,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 270),
                clockwise: false
            )
            path.closeSubpath()
        }
    }
}
