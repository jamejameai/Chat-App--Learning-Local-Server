import SwiftUI

public struct MessageComposerView: View {
    @Binding public var text: String
    public let replyingTo: ChatMessage?
    public let onCancelReply: () -> Void
    public let onSend: () -> Void
    public let onAttachmentTap: () -> Void

    public init(
        text: Binding<String>,
        replyingTo: ChatMessage?,
        onCancelReply: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onAttachmentTap: @escaping () -> Void = {}
    ) {
        self._text = text
        self.replyingTo = replyingTo
        self.onCancelReply = onCancelReply
        self.onSend = onSend
        self.onAttachmentTap = onAttachmentTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColors.border)

            // Quoted Reply Banner
            if let reply = replyingTo {
                HStack(spacing: AppSpacing.xs) {
                    Rectangle()
                        .fill(AppColors.accent)
                        .frame(width: 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("chat_replying_to", reply.senderName))
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundColor(AppColors.accent)

                        Text(reply.text)
                            .font(AppTypography.caption)
                            .lineLimit(1)
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()

                    Button(action: onCancelReply) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColors.textTertiary)
                            .font(.system(size: 16))
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.surface)
            }

            // Input Row
            HStack(alignment: .bottom, spacing: AppSpacing.xs) {
                // Attachment Button
                Button(action: onAttachmentTap) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 36, height: 36)
                }

                // Text Field
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(L("chat_composer_placeholder"))
                            .font(AppTypography.body)
                            .foregroundColor(AppColors.textTertiary)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, 8)
                    }

                    TextField("", text: $text, axis: .vertical)
                        .font(AppTypography.body)
                        .foregroundColor(AppColors.textPrimary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 8)
                        .lineLimit(1...5)
                }
                .background(AppColors.surface)
                .cornerRadius(AppCornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: AppCornerRadius.md)
                        .stroke(AppColors.border, lineWidth: 1)
                )

                // Send Button
                Button(action: onSend) {
                    ZStack {
                        Circle()
                            .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.surface : AppColors.accent)
                            .frame(width: 36, height: 36)

                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColors.textTertiary : Color.white)
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.background)
        }
    }
}
