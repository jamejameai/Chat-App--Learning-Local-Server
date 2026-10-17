import Foundation
import CryptoKit

public enum CryptoError: LocalizedError {
    case invalidSignature
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed
    case duplicateMessage
    case sessionNotInitialized
    case invalidEnvelope
    case untrustedPeer

    public var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return "Cryptographic signature validation failed"
        case .keyDerivationFailed:
            return "Key derivation function (HKDF) failed"
        case .encryptionFailed:
            return "Message encryption failed"
        case .decryptionFailed:
            return "Message decryption or authentication tag verification failed"
        case .duplicateMessage:
            return "Duplicate message detected"
        case .sessionNotInitialized:
            return "Cryptographic session is not initialized"
        case .invalidEnvelope:
            return "Invalid message envelope format"
        case .untrustedPeer:
            return "Peer identity key has changed or is untrusted"
        }
    }
}

public struct RatchetMessageEnvelope: Codable, Sendable {
    public let dhPublicKeyBase64: String
    public let messageNumber: Int
    public let previousChainLength: Int
    public let ciphertextBase64: String
    public let nonceBase64: String

    public init(
        dhPublicKeyBase64: String,
        messageNumber: Int,
        previousChainLength: Int,
        ciphertextBase64: String,
        nonceBase64: String
    ) {
        self.dhPublicKeyBase64 = dhPublicKeyBase64
        self.messageNumber = messageNumber
        self.previousChainLength = previousChainLength
        self.ciphertextBase64 = ciphertextBase64
        self.nonceBase64 = nonceBase64
    }
}

public final class DoubleRatchetSession: @unchecked Sendable {
    private let lock = NSLock()

    // DH Ratchet keys
    private var dhSenderPriv: Curve25519.KeyAgreement.PrivateKey
    private var dhSenderPub: Curve25519.KeyAgreement.PublicKey { dhSenderPriv.publicKey }
    private var dhReceiverPub: Curve25519.KeyAgreement.PublicKey?

    // Root key and Chain keys
    private var rootKey: SymmetricKey
    private var sendingChainKey: SymmetricKey?
    private var receivingChainKey: SymmetricKey?

    // Message counters
    private var sendingMessageNumber: Int = 0
    private var receivingMessageNumber: Int = 0
    private var previousChainLength: Int = 0

    // Skipped message keys cache: [CompositeKey : SymmetricKey]
    private var skippedMessageKeys: [String: SymmetricKey] = [:]
    private let maxSkippedKeys = 2000

    // Info constants for HKDF / HMAC
    private static let kdfRootInfo = Data("MiniTelegramDoubleRatchetRoot".utf8)
    private static let kdfChainInput = Data([0x01])
    private static let kdfMessageInput = Data([0x02])

    // MARK: - Initializer for Initiator (Alice)
    public init(
        sharedMasterKey: SymmetricKey,
        recipientDHPublicKey: Curve25519.KeyAgreement.PublicKey
    ) {
        let senderDH = Curve25519.KeyAgreement.PrivateKey()
        self.dhSenderPriv = senderDH
        self.dhReceiverPub = recipientDHPublicKey

        // Alice initializes DH ratchet immediately with Bob's DH key
        let dhSecret = try! senderDH.sharedSecretFromKeyAgreement(with: recipientDHPublicKey)
        let (newRK, newCKs) = DoubleRatchetSession.kdfRK(rk: sharedMasterKey, dhSecret: dhSecret)
        self.rootKey = newRK
        self.sendingChainKey = newCKs
        self.receivingChainKey = nil
        self.sendingMessageNumber = 0
        self.receivingMessageNumber = 0
        self.previousChainLength = 0
    }

    // MARK: - Initializer for Receiver (Bob)
    public init(
        sharedMasterKey: SymmetricKey,
        ownDHKeyPair: Curve25519.KeyAgreement.PrivateKey
    ) {
        self.dhSenderPriv = ownDHKeyPair
        self.dhReceiverPub = nil
        self.rootKey = sharedMasterKey
        self.sendingChainKey = nil
        self.receivingChainKey = nil
        self.sendingMessageNumber = 0
        self.receivingMessageNumber = 0
        self.previousChainLength = 0
    }

    // MARK: - Encryption (Ratchet Step)
    public func encrypt(plaintext: Data, associatedData: Data = Data()) throws -> RatchetMessageEnvelope {
        lock.lock()
        defer { lock.unlock() }

        guard let currentCKs = sendingChainKey else {
            throw CryptoError.sessionNotInitialized
        }

        // 1. Advance Sending Chain
        let (nextCKs, messageKey) = DoubleRatchetSession.kdfCK(ck: currentCKs)
        self.sendingChainKey = nextCKs

        let msgNum = sendingMessageNumber
        self.sendingMessageNumber += 1

        // 2. Encrypt with AES-GCM (256-bit)
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext, using: messageKey, nonce: nonce, authenticating: associatedData)
        let combinedCiphertext = sealedBox.ciphertext + sealedBox.tag

        let envelope = RatchetMessageEnvelope(
            dhPublicKeyBase64: dhSenderPub.rawRepresentation.base64EncodedString(),
            messageNumber: msgNum,
            previousChainLength: previousChainLength,
            ciphertextBase64: combinedCiphertext.base64EncodedString(),
            nonceBase64: Data(nonce).base64EncodedString()
        )

        return envelope
    }

    // MARK: - Decryption (Ratchet Step & Skipped Keys)
    public func decrypt(envelope: RatchetMessageEnvelope, associatedData: Data = Data()) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard let remoteDHData = Data(base64Encoded: envelope.dhPublicKeyBase64),
              let remoteDHPub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteDHData),
              let combinedCiphertextData = Data(base64Encoded: envelope.ciphertextBase64),
              let nonceData = Data(base64Encoded: envelope.nonceBase64),
              let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw CryptoError.invalidEnvelope
        }

        // Extract ciphertext and 16-byte tag
        guard combinedCiphertextData.count >= 16 else {
            throw CryptoError.decryptionFailed
        }
        let tag = combinedCiphertextData.suffix(16)
        let ciphertext = combinedCiphertextData.dropLast(16)

        let skippedKeyLookup = "\(envelope.dhPublicKeyBase64):\(envelope.messageNumber)"

        // 1. Check if we already have a skipped message key for this message
        if let skippedKey = skippedMessageKeys.removeValue(forKey: skippedKeyLookup) {
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try AES.GCM.open(sealedBox, using: skippedKey, authenticating: associatedData)
        }

        // 2. If new DH key received, perform DH Ratchet Step
        let isNewDHKey = (dhReceiverPub == nil) || (dhReceiverPub?.rawRepresentation != remoteDHPub.rawRepresentation)
        if isNewDHKey {
            // Skip messages in current receiving chain up to previousChainLength
            try skipMessageKeys(until: envelope.previousChainLength)

            // Perform DH Ratchet Step 1 (derive receiving chain with existing local DH and new remote DH)
            let dhSecret1 = try dhSenderPriv.sharedSecretFromKeyAgreement(with: remoteDHPub)
            let (rk1, nextCKr) = DoubleRatchetSession.kdfRK(rk: rootKey, dhSecret: dhSecret1)
            self.rootKey = rk1
            self.receivingChainKey = nextCKr
            self.previousChainLength = sendingMessageNumber
            self.sendingMessageNumber = 0
            self.receivingMessageNumber = 0
            self.dhReceiverPub = remoteDHPub

            // Perform DH Ratchet Step 2 (generate fresh sender DH and derive new sending chain)
            let newSenderDH = Curve25519.KeyAgreement.PrivateKey()
            self.dhSenderPriv = newSenderDH
            let dhSecret2 = try newSenderDH.sharedSecretFromKeyAgreement(with: remoteDHPub)
            let (rk2, nextCKs) = DoubleRatchetSession.kdfRK(rk: self.rootKey, dhSecret: dhSecret2)
            self.rootKey = rk2
            self.sendingChainKey = nextCKs
        }

        // 3. Skip messages in receiving chain up to envelope.messageNumber
        try skipMessageKeys(until: envelope.messageNumber)

        // 4. Advance Receiving Chain to derive message key
        guard let currentCKr = receivingChainKey else {
            throw CryptoError.sessionNotInitialized
        }
        let (nextCKr, messageKey) = DoubleRatchetSession.kdfCK(ck: currentCKr)
        self.receivingChainKey = nextCKr
        self.receivingMessageNumber += 1

        // 5. Decrypt with AES-GCM
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decrypted = try AES.GCM.open(sealedBox, using: messageKey, authenticating: associatedData)

        return decrypted
    }

    private func skipMessageKeys(until untilNumber: Int) throws {
        guard let currentCKr = receivingChainKey, let currentDHr = dhReceiverPub else {
            return
        }
        if receivingMessageNumber + 100 < untilNumber {
            throw CryptoError.decryptionFailed // Too many skipped messages
        }

        var workingCK = currentCKr
        let dhBase64 = currentDHr.rawRepresentation.base64EncodedString()

        while receivingMessageNumber < untilNumber {
            let (nextCK, mk) = DoubleRatchetSession.kdfCK(ck: workingCK)
            workingCK = nextCK
            let keyLookup = "\(dhBase64):\(receivingMessageNumber)"
            if skippedMessageKeys.count < maxSkippedKeys {
                skippedMessageKeys[keyLookup] = mk
            }
            self.receivingMessageNumber += 1
        }
        self.receivingChainKey = workingCK
    }

    // MARK: - Key Derivation Functions (KDF)
    private static func kdfRK(
        rk: SymmetricKey,
        dhSecret: SharedSecret
    ) -> (newRK: SymmetricKey, newCK: SymmetricKey) {
        let derivedKeyData = dhSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: rk.withUnsafeBytes { Data($0) },
            sharedInfo: kdfRootInfo,
            outputByteCount: 64
        )

        let derivedBytes = derivedKeyData.withUnsafeBytes { Array($0) }
        let nextRK = SymmetricKey(data: derivedBytes[0..<32])
        let nextCK = SymmetricKey(data: derivedBytes[32..<64])
        return (nextRK, nextCK)
    }

    private static func kdfCK(ck: SymmetricKey) -> (nextCK: SymmetricKey, messageKey: SymmetricKey) {
        let hmacNextCK = HMAC<SHA256>.authenticationCode(for: kdfChainInput, using: ck)
        let hmacMK = HMAC<SHA256>.authenticationCode(for: kdfMessageInput, using: ck)
        return (SymmetricKey(data: hmacNextCK), SymmetricKey(data: hmacMK))
    }
}
