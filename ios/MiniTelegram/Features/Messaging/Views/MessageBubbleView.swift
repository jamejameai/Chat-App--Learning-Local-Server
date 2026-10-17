import SwiftUI

public struct MessageBubbleView: View {
    public let message: ChatMessage
    public let onReply: (ChatMessage) -> Void
    public let onReact: (ChatMessage, String) -> Void

    private let availableEmojis = ["❤️", "👍", "👎", "😂", "😮", "🙏"]

    public init(
        message: ChatMessage,
        onReply: @escaping (ChatMessage) -> Void,
        onReact: @escaping (ChatMessage, String) -> Void
    ) {
        self.message = message
        self.onReply = onReply
        self.onReact = onReact
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
                    if !message.isOutgoing && !message.senderName.isEmpty {
                        Text(message.senderName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppColors.accent)
                    }

                    // Quoted Reply Preview
                    if let replyText = message.replyPreview {
                        HStack(spacing: AppSpacing.xs) {
                            Rectangle()
                                .fill(message.isOutgoing ? Color.white.opacity(0.8) : AppColors.accent)
                                .frame(width: 3)

                            Text(replyText)
                                .font(AppTypography.caption)
                                .lineLimit(2)
                                .foregroundColor(message.isOutgoing ? Color.white.opacity(0.9) : AppColors.textSecondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(message.isOutgoing ? Color.white.opacity(0.15) : AppColors.background)
                        .cornerRadius(AppCornerRadius.sm)
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

                    // Message Text
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(AppTypography.body)
                            .foregroundColor(message.isOutgoing ? Color.white : AppColors.textPrimary)
                    }

                    // Footer: Timestamp & Delivery Status
                    HStack(spacing: 4) {
                        Spacer(minLength: 16)

                        Text(formattedTime(message.timestamp))
                            .font(.system(size: 11))
                            .foregroundColor(message.isOutgoing ? Color.white.opacity(0.7) : AppColors.textTertiary)

                        if message.isOutgoing {
                            statusIcon(message.status)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xs)
                .background(bubbleBackground)
                .clipShape(BubbleShape(isOutgoing: message.isOutgoing))

                // Reaction Ribbon
                if !message.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(message.reactions) { reaction in
                            HStack(spacing: 2) {
                                Text(reaction.emoji)
                                    .font(.system(size: 12))
                                if reaction.count > 1 {
                                    Text("\(reaction.count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(AppColors.textPrimary)
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.surface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(AppColors.border, lineWidth: 1)
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
                    ForEach(availableEmojis, id: \.self) { emoji in
                        Button(action: {
                            onReact(message, emoji)
                        }) {
                            Label(emoji, systemImage: "face.smiling")
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

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.isOutgoing {
            LinearGradient(
                colors: [AppColors.accent, AppColors.accent.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            AppColors.surface
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: MessageDeliveryStatus) -> some View {
        switch status {
        case .sending:
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.7))
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.8))
        case .delivered:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.8))
        case .read:
            HStack(spacing: -3) {
                Image(systemName: "checkmark")
                Image(systemName: "checkmark")
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(AppColors.readReceipt)
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
