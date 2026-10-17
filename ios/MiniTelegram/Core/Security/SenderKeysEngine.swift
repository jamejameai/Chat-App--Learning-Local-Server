import Foundation
import CryptoKit

public struct GroupMessageEnvelope: Codable, Sendable {
    public let senderUserId: String
    public let senderDeviceId: String
    public let iteration: Int
    public let ciphertextBase64: String
    public let nonceBase64: String
    public let signatureBase64: String

    public init(
        senderUserId: String,
        senderDeviceId: String,
        iteration: Int,
        ciphertextBase64: String,
        nonceBase64: String,
        signatureBase64: String
    ) {
        self.senderUserId = senderUserId
        self.senderDeviceId = senderDeviceId
        self.iteration = iteration
        self.ciphertextBase64 = ciphertextBase64
        self.nonceBase64 = nonceBase64
        self.signatureBase64 = signatureBase64
    }
}

public struct SenderKeyDistributionMessage: Codable, Sendable {
    public let groupId: String
    public let senderUserId: String
    public let senderDeviceId: String
    public let chainKeyBase64: String
    public let iteration: Int
    public let signingPublicKeyBase64: String

    public init(
        groupId: String,
        senderUserId: String,
        senderDeviceId: String,
        chainKeyBase64: String,
        iteration: Int,
        signingPublicKeyBase64: String
    ) {
        self.groupId = groupId
        self.senderUserId = senderUserId
        self.senderDeviceId = senderDeviceId
        self.chainKeyBase64 = chainKeyBase64
        self.iteration = iteration
        self.signingPublicKeyBase64 = signingPublicKeyBase64
    }
}

public final class SenderKeySession: @unchecked Sendable {
    private let lock = NSLock()

    public let groupId: String
    public let senderUserId: String
    public let senderDeviceId: String

    private var chainKey: SymmetricKey
    private var iteration: Int
    private var messageKeys: [Int: SymmetricKey] = [:]
    private let signingPrivateKey: Curve25519.Signing.PrivateKey?
    private let signingPublicKey: Curve25519.Signing.PublicKey

    private static let chainInput = Data([0x01])
    private static let messageInput = Data([0x02])

    // Outbound Sender Key Session (We are the sender)
    public init(
        groupId: String,
        senderUserId: String,
        senderDeviceId: String
    ) {
        self.groupId = groupId
        self.senderUserId = senderUserId
        self.senderDeviceId = senderDeviceId
        self.chainKey = SymmetricKey(size: .bits256)
        self.iteration = 0
        let signingPriv = Curve25519.Signing.PrivateKey()
        self.signingPrivateKey = signingPriv
        self.signingPublicKey = signingPriv.publicKey
    }

    // Inbound Sender Key Session (Another group participant is the sender)
    public init(
        distribution: SenderKeyDistributionMessage
    ) throws {
        self.groupId = distribution.groupId
        self.senderUserId = distribution.senderUserId
        self.senderDeviceId = distribution.senderDeviceId
        guard let chainData = Data(base64Encoded: distribution.chainKeyBase64),
              let signPubData = Data(base64Encoded: distribution.signingPublicKeyBase64) else {
            throw CryptoError.invalidEnvelope
        }
        self.chainKey = SymmetricKey(data: chainData)
        self.iteration = distribution.iteration
        self.signingPrivateKey = nil
        self.signingPublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: signPubData)
    }

    public func createDistributionMessage() -> SenderKeyDistributionMessage {
        lock.lock()
        defer { lock.unlock() }

        let chainBase64 = chainKey.withUnsafeBytes { Data($0).base64EncodedString() }
        return SenderKeyDistributionMessage(
            groupId: groupId,
            senderUserId: senderUserId,
            senderDeviceId: senderDeviceId,
            chainKeyBase64: chainBase64,
            iteration: iteration,
            signingPublicKeyBase64: signingPublicKey.rawRepresentation.base64EncodedString()
        )
    }

    public func encrypt(plaintext: Data) throws -> GroupMessageEnvelope {
        lock.lock()
        defer { lock.unlock() }

        guard let signingPriv = signingPrivateKey else {
            throw CryptoError.encryptionFailed
        }

        // 1. Advance symmetric chain
        let (nextCK, mk) = SenderKeySession.kdfChain(ck: chainKey)
        self.chainKey = nextCK
        let currentIter = iteration
        self.iteration += 1
        self.messageKeys[currentIter] = mk

        // 2. Encrypt with AES-GCM
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext, using: mk, nonce: nonce)
        let ciphertext = sealedBox.ciphertext + sealedBox.tag

        // 3. Sign ciphertext with Ed25519
        let signature = try signingPriv.signature(for: ciphertext)

        return GroupMessageEnvelope(
            senderUserId: senderUserId,
            senderDeviceId: senderDeviceId,
            iteration: currentIter,
            ciphertextBase64: ciphertext.base64EncodedString(),
            nonceBase64: Data(nonce).base64EncodedString(),
            signatureBase64: signature.base64EncodedString()
        )
    }

    public func decrypt(envelope: GroupMessageEnvelope) throws -> Data {
        lock.lock()
        defer { lock.unlock() }

        guard let ciphertextData = Data(base64Encoded: envelope.ciphertextBase64),
              let nonceData = Data(base64Encoded: envelope.nonceBase64),
              let sigData = Data(base64Encoded: envelope.signatureBase64),
              let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw CryptoError.invalidEnvelope
        }

        // 1. Verify Ed25519 signature
        guard signingPublicKey.isValidSignature(sigData, for: ciphertextData) else {
            throw CryptoError.invalidSignature
        }

        // 2. Fetch or advance message key
        let mk: SymmetricKey
        if envelope.iteration < self.iteration {
            guard let cachedMK = messageKeys[envelope.iteration] else {
                throw CryptoError.duplicateMessage
            }
            mk = cachedMK
        } else {
            var workingCK = self.chainKey
            var currentIter = self.iteration

            while currentIter < envelope.iteration {
                let (nextCK, skippedMK) = SenderKeySession.kdfChain(ck: workingCK)
                self.messageKeys[currentIter] = skippedMK
                workingCK = nextCK
                currentIter += 1
            }

            let (nextCK, currentMK) = SenderKeySession.kdfChain(ck: workingCK)
            self.chainKey = nextCK
            self.iteration = currentIter + 1
            self.messageKeys[envelope.iteration] = currentMK
            mk = currentMK
        }

        // 3. Decrypt with AES-GCM
        guard ciphertextData.count >= 16 else {
            throw CryptoError.decryptionFailed
        }
        let tag = ciphertextData.suffix(16)
        let rawCiphertext = ciphertextData.dropLast(16)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: rawCiphertext, tag: tag)

        return try AES.GCM.open(sealedBox, using: mk)
    }

    private static func kdfChain(ck: SymmetricKey) -> (nextCK: SymmetricKey, messageKey: SymmetricKey) {
        let hmacNextCK = HMAC<SHA256>.authenticationCode(for: chainInput, using: ck)
        let hmacMK = HMAC<SHA256>.authenticationCode(for: messageInput, using: ck)
        return (SymmetricKey(data: hmacNextCK), SymmetricKey(data: hmacMK))
    }
}
