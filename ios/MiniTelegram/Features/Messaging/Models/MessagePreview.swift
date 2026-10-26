import Foundation

/// One-line preview of a message for the chat list and notifications.
public enum MessagePreview {
    public static func text(text: String, attachment: MessageAttachment?, voiceNote: VoiceNoteMetadata?) -> String {
        if let voiceNote {
            return "🎤 Voice message (\(Int(voiceNote.durationSeconds))s)"
        }
        if let attachment {
            return attachment.mimeType.hasPrefix("image/") ? "📷 Photo" : "📎 \(attachment.fileName)"
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Message" : trimmed
    }

    public static func text(for message: ChatMessage) -> String {
        let body = text(text: message.text, attachment: message.attachment, voiceNote: message.voiceNote)
        return message.isOutgoing ? "You: \(body)" : body
    }
}
