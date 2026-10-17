import Foundation
import CryptoKit

public struct PrekeyPair {
    public let keyId: Int
    public let privateKey: Curve25519.KeyAgreement.PrivateKey
    public let publicKeyBase64: String
}

public struct GeneratedDeviceKeys {
    public let identityAgreementPrivateKey: Curve25519.KeyAgreement.PrivateKey
    public let identitySigningPrivateKey: Curve25519.Signing.PrivateKey
    public let identityAgreementPublicKeyBase64: String
    public let identitySigningPublicKeyBase64: String

    public let signedPrekeyId: Int
    public let signedPrekeyPrivateKey: Curve25519.KeyAgreement.PrivateKey
    public let signedPrekeyPublicKeyBase64: String
    public let signedPrekeySignatureBase64: String

    public let oneTimePrekeys: [PrekeyPair]
    public let identityFingerprint: String
}

public final class CryptoIdentityService: Sendable {
    public static let shared = CryptoIdentityService()

    private init() {}

    public func generateInitialDeviceKeys(oneTimePrekeyCount: Int = 50) throws -> GeneratedDeviceKeys {
        // 1. Identity Key Agreement (X25519)
        let identityAgreementPriv = Curve25519.KeyAgreement.PrivateKey()
        let identityAgreementPub = identityAgreementPriv.publicKey
        let identityAgreementPubBase64 = identityAgreementPub.rawRepresentation.base64EncodedString()

        // 2. Identity Signing Key (Ed25519)
        let identitySigningPriv = Curve25519.Signing.PrivateKey()
        let identitySigningPub = identitySigningPriv.publicKey
        let identitySigningPubBase64 = identitySigningPub.rawRepresentation.base64EncodedString()

        // 3. Signed Prekey (X25519)
        let signedPrekeyId = 1
        let signedPrekeyPriv = Curve25519.KeyAgreement.PrivateKey()
        let signedPrekeyPub = signedPrekeyPriv.publicKey
        let signedPrekeyPubBase64 = signedPrekeyPub.rawRepresentation.base64EncodedString()

        // Sign the prekey with the Ed25519 identity key
        let signedPrekeySig = try identitySigningPriv.signature(for: signedPrekeyPub.rawRepresentation)
        let signedPrekeySigBase64 = signedPrekeySig.base64EncodedString()

        // 4. One-Time Prekeys pool
        var oneTimePrekeys: [PrekeyPair] = []
        for i in 1...oneTimePrekeyCount {
            let opkPriv = Curve25519.KeyAgreement.PrivateKey()
            let opkPubBase64 = opkPriv.publicKey.rawRepresentation.base64EncodedString()
            oneTimePrekeys.append(PrekeyPair(keyId: i, privateKey: opkPriv, publicKeyBase64: opkPubBase64))
        }

        // 5. Compute formatted identity fingerprint
        let fingerprintDigest = SHA256.hash(data: identityAgreementPub.rawRepresentation)
        let fingerprint = formatFingerprint(data: Data(fingerprintDigest))

        return GeneratedDeviceKeys(
            identityAgreementPrivateKey: identityAgreementPriv,
            identitySigningPrivateKey: identitySigningPriv,
            identityAgreementPublicKeyBase64: identityAgreementPubBase64,
            identitySigningPublicKeyBase64: identitySigningPubBase64,
            signedPrekeyId: signedPrekeyId,
            signedPrekeyPrivateKey: signedPrekeyPriv,
            signedPrekeyPublicKeyBase64: signedPrekeyPubBase64,
            signedPrekeySignatureBase64: signedPrekeySigBase64,
            oneTimePrekeys: oneTimePrekeys,
            identityFingerprint: fingerprint
        )
    }

    public func formatFingerprint(data: Data) -> String {
        // Take first 15 bytes and format into 6 blocks of 5 decimal digits
        var numbers: [String] = []
        let bytes = Array(data.prefix(15))
        for i in stride(from: 0, to: bytes.count, by: 2) {
            if i + 1 < bytes.count {
                let val = (UInt32(bytes[i]) << 8) | UInt32(bytes[i + 1])
                let block = String(format: "%05d", val % 100000)
                numbers.append(block)
            }
        }
        return numbers.joined(separator: " ")
    }
}
