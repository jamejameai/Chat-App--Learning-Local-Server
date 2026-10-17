import Foundation
import CryptoKit

public struct X3DHPrekeyBundle: Sendable {
    public let identityAgreementPublicKey: Curve25519.KeyAgreement.PublicKey
    public let identitySigningPublicKey: Curve25519.Signing.PublicKey
    public let signedPrekeyPublicKey: Curve25519.KeyAgreement.PublicKey
    public let signedPrekeySignature: Data
    public let signedPrekeyId: Int
    public let oneTimePrekeyPublicKey: Curve25519.KeyAgreement.PublicKey?
    public let oneTimePrekeyId: Int?

    public init(
        identityAgreementPublicKey: Curve25519.KeyAgreement.PublicKey,
        identitySigningPublicKey: Curve25519.Signing.PublicKey,
        signedPrekeyPublicKey: Curve25519.KeyAgreement.PublicKey,
        signedPrekeySignature: Data,
        signedPrekeyId: Int,
        oneTimePrekeyPublicKey: Curve25519.KeyAgreement.PublicKey? = nil,
        oneTimePrekeyId: Int? = nil
    ) {
        self.identityAgreementPublicKey = identityAgreementPublicKey
        self.identitySigningPublicKey = identitySigningPublicKey
        self.signedPrekeyPublicKey = signedPrekeyPublicKey
        self.signedPrekeySignature = signedPrekeySignature
        self.signedPrekeyId = signedPrekeyId
        self.oneTimePrekeyPublicKey = oneTimePrekeyPublicKey
        self.oneTimePrekeyId = oneTimePrekeyId
    }
}

public struct X3DHInitiatorResult: Sendable {
    public let masterSharedKey: SymmetricKey
    public let ephemeralPublicKey: Curve25519.KeyAgreement.PublicKey
    public let usedOneTimePrekeyId: Int?
}

public final class X3DHEngine: Sendable {
    public static let shared = X3DHEngine()

    private static let x3dhInfo = Data("MiniTelegramX3DHProtocol".utf8)

    private init() {}

    // MARK: - Alice (Initiator)
    public func initiateSession(
        aliceIdentityKey: Curve25519.KeyAgreement.PrivateKey,
        bobBundle: X3DHPrekeyBundle
    ) throws -> X3DHInitiatorResult {
        // 1. Verify Bob's Signed Prekey signature
        let isSignatureValid = bobBundle.identitySigningPublicKey.isValidSignature(
            bobBundle.signedPrekeySignature,
            for: bobBundle.signedPrekeyPublicKey.rawRepresentation
        )
        guard isSignatureValid else {
            throw CryptoError.invalidSignature
        }

        // 2. Generate Ephemeral Key (EK_A)
        let aliceEphemeralKey = Curve25519.KeyAgreement.PrivateKey()

        // 3. Perform Diffie-Hellman calculations
        // DH1 = X25519(IK_A_priv, SPK_B_pub)
        let dh1 = try aliceIdentityKey.sharedSecretFromKeyAgreement(with: bobBundle.signedPrekeyPublicKey)
        // DH2 = X25519(EK_A_priv, IK_B_pub)
        let dh2 = try aliceEphemeralKey.sharedSecretFromKeyAgreement(with: bobBundle.identityAgreementPublicKey)
        // DH3 = X25519(EK_A_priv, SPK_B_pub)
        let dh3 = try aliceEphemeralKey.sharedSecretFromKeyAgreement(with: bobBundle.signedPrekeyPublicKey)

        var combinedSecrets = dh1.withUnsafeBytes { Data($0) }
        combinedSecrets.append(dh2.withUnsafeBytes { Data($0) })
        combinedSecrets.append(dh3.withUnsafeBytes { Data($0) })

        // DH4 = X25519(EK_A_priv, OPK_B_pub) (if OPK available)
        var usedOPKId: Int? = nil
        if let opk = bobBundle.oneTimePrekeyPublicKey {
            let dh4 = try aliceEphemeralKey.sharedSecretFromKeyAgreement(with: opk)
            combinedSecrets.append(dh4.withUnsafeBytes { Data($0) })
            usedOPKId = bobBundle.oneTimePrekeyId
        }

        // 4. Derive Master Shared Key (SK) via HKDF
        let masterSharedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: combinedSecrets),
            info: Self.x3dhInfo,
            outputByteCount: 32
        )

        return X3DHInitiatorResult(
            masterSharedKey: masterSharedKey,
            ephemeralPublicKey: aliceEphemeralKey.publicKey,
            usedOneTimePrekeyId: usedOPKId
        )
    }

    // MARK: - Bob (Receiver)
    public func receiveSession(
        bobIdentityKey: Curve25519.KeyAgreement.PrivateKey,
        bobSignedPrekey: Curve25519.KeyAgreement.PrivateKey,
        bobOneTimePrekey: Curve25519.KeyAgreement.PrivateKey?,
        aliceIdentityPublicKey: Curve25519.KeyAgreement.PublicKey,
        aliceEphemeralPublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> SymmetricKey {
        // DH1 = X25519(SPK_B_priv, IK_A_pub)
        let dh1 = try bobSignedPrekey.sharedSecretFromKeyAgreement(with: aliceIdentityPublicKey)
        // DH2 = X25519(IK_B_priv, EK_A_pub)
        let dh2 = try bobIdentityKey.sharedSecretFromKeyAgreement(with: aliceEphemeralPublicKey)
        // DH3 = X25519(SPK_B_priv, EK_A_pub)
        let dh3 = try bobSignedPrekey.sharedSecretFromKeyAgreement(with: aliceEphemeralPublicKey)

        var combinedSecrets = dh1.withUnsafeBytes { Data($0) }
        combinedSecrets.append(dh2.withUnsafeBytes { Data($0) })
        combinedSecrets.append(dh3.withUnsafeBytes { Data($0) })

        // DH4 = X25519(OPK_B_priv, EK_A_pub) (if OPK used)
        if let opkPriv = bobOneTimePrekey {
            let dh4 = try opkPriv.sharedSecretFromKeyAgreement(with: aliceEphemeralPublicKey)
            combinedSecrets.append(dh4.withUnsafeBytes { Data($0) })
        }

        // Derive identical Master Shared Key (SK)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: combinedSecrets),
            info: Self.x3dhInfo,
            outputByteCount: 32
        )
    }
}
