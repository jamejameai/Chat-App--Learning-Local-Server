import Foundation
import CryptoKit

public struct InnerMessagePayload: Codable, Sendable {
    public let text: String
    public let replyToMessageId: String?
    public let reactionEmoji: String?
    public let reactionTargetMessageId: String?

    public init(
        text: String,
        replyToMessageId: String? = nil,
        reactionEmoji: String? = nil,
        reactionTargetMessageId: String? = nil
    ) {
        self.text = text
        self.replyToMessageId = replyToMessageId
        self.reactionEmoji = reactionEmoji
        self.reactionTargetMessageId = reactionTargetMessageId
    }
}

public final class MessageCryptoCoordinator: @unchecked Sendable {
    public static let shared = MessageCryptoCoordinator()

    private let lock = NSLock()
    // In-memory active Double Ratchet sessions keyed by conversationId or peerUserId
    private var ratchetSessions: [String: DoubleRatchetSession] = [:]

    private init() {}

    public func encryptMessage(
        conversationId: String,
        text: String,
        replyToMessageId: String? = nil
    ) throws -> (payloadBase64: String, ivBase64: String, envelopeType: String) {
        lock.lock()
        defer { lock.unlock() }

        let inner = InnerMessagePayload(text: text, replyToMessageId: replyToMessageId)
        let innerData = try JSONEncoder().encode(inner)

        if let session = ratchetSessions[conversationId] {
            let env = try session.encrypt(plaintext: innerData)
            let envData = try JSONEncoder().encode(env)
            return (
                payloadBase64: envData.base64EncodedString(),
                ivBase64: env.nonceBase64,
                envelopeType: "double_ratchet"
            )
        } else {
            // Ephemeral AES-GCM encryption for initial direct message envelope
            let key = SymmetricKey(size: .bits256)
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
    ) -> String {
        lock.lock()
        defer { lock.unlock() }

        // 1. Try decoding as DoubleRatchet RatchetMessageEnvelope
        if let envData = Data(base64Encoded: encryptedPayloadBase64),
           let env = try? JSONDecoder().decode(RatchetMessageEnvelope.self, from: envData),
           let session = ratchetSessions[conversationId],
           let decryptedData = try? session.decrypt(envelope: env),
           let inner = try? JSONDecoder().decode(InnerMessagePayload.self, from: decryptedData) {
            return inner.text
        }

        // 2. Try raw UTF-8 fallback (for plaintext demo mode or testing)
        if let data = Data(base64Encoded: encryptedPayloadBase64),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        return encryptedPayloadBase64
    }

    public func registerSession(conversationId: String, session: DoubleRatchetSession) {
        lock.lock()
        defer { lock.unlock() }
        ratchetSessions[conversationId] = session
    }
}
