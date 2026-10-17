import Foundation
import CryptoKit

public final class FrameCryptorManager: @unchecked Sendable {
    public static let shared = FrameCryptorManager()

    private let emojiTable = [
        "🦊", "🐼", "🦁", "🐯", "🐨", "🐸", "🐙", "🐬",
        "🍎", "🍓", "🍇", "🍒", "🥑", "🍕", "⚡", "🚀",
        "💎", "🔒", "🛡️", "🔥", "🌟", "🎉", "🌈", "🪐",
        "⚽", "🎸", "🏆", "🧭", "🛸", "⛵", "🏔️", "🏝️"
    ]

    private init() {}

    public func deriveCallKey(sharedSecret: SymmetricKey, callId: String) -> SymmetricKey {
        let salt = "MiniTelegram-Calling-Salt-v1".data(using: .utf8)!
        let info = "MiniTelegram-WebRTC-FrameCryptor-\(callId)".data(using: .utf8)!

        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: sharedSecret,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        return derived
    }

    public func computeVerificationFingerprint(key: SymmetricKey) -> String {
        let digest = SHA256.hash(data: key.withUnsafeBytes { Data($0) })
        let bytes = Array(digest)

        // Select 4 emojis deterministically from the 32-byte digest
        let e1 = emojiTable[Int(bytes[0]) % emojiTable.count]
        let e2 = emojiTable[Int(bytes[1]) % emojiTable.count]
        let e3 = emojiTable[Int(bytes[2]) % emojiTable.count]
        let e4 = emojiTable[Int(bytes[3]) % emojiTable.count]

        return "\(e1) \(e2) \(e3) \(e4)"
    }

    public func encryptFrame(rawFrame: Data, key: SymmetricKey, frameIndex: UInt64) throws -> Data {
        // Construct unique 12-byte nonce using frame index (SFrame format)
        var nonceBytes = [UInt8](repeating: 0, count: 12)
        var indexLE = frameIndex.littleEndian
        withUnsafeBytes(of: &indexLE) { ptr in
            for i in 0..<min(8, ptr.count) {
                nonceBytes[i] = ptr[i]
            }
        }
        let nonce = try AES.GCM.Nonce(data: nonceBytes)

        let sealed = try AES.GCM.seal(rawFrame, using: key, nonce: nonce)
        return sealed.ciphertext + sealed.tag
    }

    public func decryptFrame(encryptedFrame: Data, key: SymmetricKey, frameIndex: UInt64) throws -> Data {
        guard encryptedFrame.count >= 16 else {
            throw CryptoError.decryptionFailed
        }

        var nonceBytes = [UInt8](repeating: 0, count: 12)
        var indexLE = frameIndex.littleEndian
        withUnsafeBytes(of: &indexLE) { ptr in
            for i in 0..<min(8, ptr.count) {
                nonceBytes[i] = ptr[i]
            }
        }
        let nonce = try AES.GCM.Nonce(data: nonceBytes)

        let tag = encryptedFrame.suffix(16)
        let ciphertext = encryptedFrame.dropLast(16)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)

        return try AES.GCM.open(sealed, using: key)
    }
}
