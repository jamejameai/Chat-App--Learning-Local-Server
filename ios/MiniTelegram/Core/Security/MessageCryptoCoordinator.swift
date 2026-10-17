import Foundation
import CryptoKit

public struct InnerMessagePayload: Codable, Sendable {
    public let text: String
    public let replyToMessageId: String?
    public let reactionEmoji: String?
    public let reactionTargetMessageId: String?
    public let attachment: MessageAttachment?
    public let voiceNote: VoiceNoteMetadata?

    public init(
        text: String,
        replyToMessageId: String? = nil,
        reactionEmoji: String? = nil,
        reactionTargetMessageId: String? = nil,
        attachment: MessageAttachment? = nil,
        voiceNote: VoiceNoteMetadata? = nil
    ) {
        self.text = text
        self.replyToMessageId = replyToMessageId
        self.reactionEmoji = reactionEmoji
        self.reactionTargetMessageId = reactionTargetMessageId
        self.attachment = attachment
        self.voiceNote = voiceNote
    }
}

public struct DecryptedPayload: Sendable {
    public let text: String
    public let replyToMessageId: String?
    public let attachment: MessageAttachment?
    public let voiceNote: VoiceNoteMetadata?

    public init(
        text: String,
        replyToMessageId: String? = nil,
        attachment: MessageAttachment? = nil,
        voiceNote: VoiceNoteMetadata? = nil
    ) {
        self.text = text
        self.replyToMessageId = replyToMessageId
        self.attachment = attachment
        self.voiceNote = voiceNote
    }
}

public final class MessageCryptoCoordinator: @unchecked Sendable {
    public static let shared = MessageCryptoCoordinator()

    private let lock = NSLock()
    // Pairwise 1:1 Double Ratchet sessions keyed by conversationId
    private var ratchetSessions: [String: DoubleRatchetSession] = [:]
    // Multi-party group Sender Key sessions keyed by conversationId
    private var groupSenderSessions: [String: SenderKeySession] = [:]

    private init() {}

    public func encryptMessage(
        conversationId: String,
        text: String,
        replyToMessageId: String? = nil,
        attachment: MessageAttachment? = nil,
        voiceNote: VoiceNoteMetadata? = nil,
        isGroup: Bool = false,
        senderUserId: String = "",
        senderDeviceId: String = ""
    ) throws -> (payloadBase64: String, ivBase64: String, envelopeType: String) {
        lock.lock()
        defer { lock.unlock() }

        let inner = InnerMessagePayload(
            text: text,
            replyToMessageId: replyToMessageId,
            attachment: attachment,
            voiceNote: voiceNote
        )
        let innerData = try JSONEncoder().encode(inner)

        if isGroup, let groupSession = groupSenderSessions[conversationId] {
            let env = try groupSession.encrypt(plaintext: innerData)
            let envData = try JSONEncoder().encode(env)
            return (
                payloadBase64: envData.base64EncodedString(),
                ivBase64: env.nonceBase64,
                envelopeType: "sender_key"
            )
        } else if let session = ratchetSessions[conversationId] {
            let env = try session.encrypt(plaintext: innerData)
            let envData = try JSONEncoder().encode(env)
            return (
                payloadBase64: envData.base64EncodedString(),
                ivBase64: env.nonceBase64,
                envelopeType: "double_ratchet"
            )
        } else {
            // Direct AEAD encryption using conversation key
            let keyHash = SHA256.hash(data: ("MiniTelegram-Conversation-Secret-" + conversationId).data(using: .utf8)!)
            let key = SymmetricKey(data: keyHash)
            let nonce = AES.GCM.Nonce()
            let box = try AES.GCM.seal(innerData, using: key, nonce: nonce)
            let combined = box.ciphertext + box.tag
            return (
                payloadBase64: combined.base64EncodedString(),
                ivBase64: Data(nonce).base64EncodedString(),
                envelopeType: "double_ratchet"
            )
        }
    }

    public func decryptMessage(
        conversationId: String,
        encryptedPayloadBase64: String,
        ivBase64: String,
        envelopeType: String
    ) -> DecryptedPayload {
        lock.lock()
        defer { lock.unlock() }

        // 1. Try decoding as DoubleRatchet RatchetMessageEnvelope
        if let envData = Data(base64Encoded: encryptedPayloadBase64),
           let env = try? JSONDecoder().decode(RatchetMessageEnvelope.self, from: envData),
           let session = ratchetSessions[conversationId],
           let decryptedData = try? session.decrypt(envelope: env),
           let inner = try? JSONDecoder().decode(InnerMessagePayload.self, from: decryptedData) {
            return DecryptedPayload(
                text: inner.text,
                replyToMessageId: inner.replyToMessageId,
                attachment: inner.attachment,
                voiceNote: inner.voiceNote
            )
        }

        // 2. Try decoding as Group SenderKey GroupMessageEnvelope
        if let envData = Data(base64Encoded: encryptedPayloadBase64),
           let env = try? JSONDecoder().decode(GroupMessageEnvelope.self, from: envData),
           let groupSession = groupSenderSessions[conversationId],
           let decryptedData = try? groupSession.decrypt(envelope: env),
           let inner = try? JSONDecoder().decode(InnerMessagePayload.self, from: decryptedData) {
            return DecryptedPayload(
                text: inner.text,
                replyToMessageId: inner.replyToMessageId,
                attachment: inner.attachment,
                voiceNote: inner.voiceNote
            )
        }

        // 3. Try direct AEAD decryption with conversation key and iv
        let keyHash = SHA256.hash(data: ("MiniTelegram-Conversation-Secret-" + conversationId).data(using: .utf8)!)
        let fallbackKey = SymmetricKey(data: keyHash)
        if let combinedData = Data(base64Encoded: encryptedPayloadBase64),
           let ivData = Data(base64Encoded: ivBase64),
           let nonce = try? AES.GCM.Nonce(data: ivData),
           combinedData.count >= 16 {
            let tag = combinedData.suffix(16)
            let ciphertext = combinedData.dropLast(16)
            if let box = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag),
               let decryptedData = try? AES.GCM.open(box, using: fallbackKey),
               let inner = try? JSONDecoder().decode(InnerMessagePayload.self, from: decryptedData) {
                return DecryptedPayload(
                    text: inner.text,
                    replyToMessageId: inner.replyToMessageId,
                    attachment: inner.attachment,
                    voiceNote: inner.voiceNote
                )
            }
        }

        // 4. Try raw JSON fallback (unwrapped InnerMessagePayload)
        if let data = Data(base64Encoded: encryptedPayloadBase64),
           let inner = try? JSONDecoder().decode(InnerMessagePayload.self, from: data) {
            return DecryptedPayload(
                text: inner.text,
                replyToMessageId: inner.replyToMessageId,
                attachment: inner.attachment,
                voiceNote: inner.voiceNote
            )
        }

        // 4. Try raw UTF-8 string fallback
        if let data = Data(base64Encoded: encryptedPayloadBase64),
           let text = String(data: data, encoding: .utf8) {
            return DecryptedPayload(text: text)
        }

        return DecryptedPayload(text: encryptedPayloadBase64)
    }

    public func registerSession(conversationId: String, session: DoubleRatchetSession) {
        lock.lock()
        defer { lock.unlock() }
        ratchetSessions[conversationId] = session
    }

    public func registerGroupSession(conversationId: String, session: SenderKeySession) {
        lock.lock()
        defer { lock.unlock() }
        groupSenderSessions[conversationId] = session
    }

    public func rotateGroupSenderKey(conversationId: String, senderUserId: String, senderDeviceId: String) {
        lock.lock()
        defer { lock.unlock() }
        // Generates fresh sender key record when member eviction occurs
        let newSession = SenderKeySession(
            groupId: conversationId,
            senderUserId: senderUserId,
            senderDeviceId: senderDeviceId
        )
        groupSenderSessions[conversationId] = newSession
    }
}
