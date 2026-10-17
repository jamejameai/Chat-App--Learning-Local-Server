import XCTest
import CryptoKit
@testable import MiniTelegram

final class X3DHTests: XCTestCase {

    func testCompleteX3DHKeyAgreement() throws {
        // 1. Bob provisions identity and prekeys
        let bobIdentityKeyAgreementPriv = Curve25519.KeyAgreement.PrivateKey()
        let bobIdentitySigningPriv = Curve25519.Signing.PrivateKey()
        let bobSignedPrekeyPriv = Curve25519.KeyAgreement.PrivateKey()
        let bobOneTimePrekeyPriv = Curve25519.KeyAgreement.PrivateKey()

        // Bob signs his prekey
        let bobSignature = try bobIdentitySigningPriv.signature(for: bobSignedPrekeyPriv.publicKey.rawRepresentation)

        let bobBundle = X3DHPrekeyBundle(
            identityAgreementPublicKey: bobIdentityKeyAgreementPriv.publicKey,
            identitySigningPublicKey: bobIdentitySigningPriv.publicKey,
            signedPrekeyPublicKey: bobSignedPrekeyPriv.publicKey,
            signedPrekeySignature: bobSignature,
            signedPrekeyId: 1,
            oneTimePrekeyPublicKey: bobOneTimePrekeyPriv.publicKey,
            oneTimePrekeyId: 42
        )

        // 2. Alice initiates X3DH session
        let aliceIdentityKeyAgreementPriv = Curve25519.KeyAgreement.PrivateKey()

        let initiatorResult = try X3DHEngine.shared.initiateSession(
            aliceIdentityKey: aliceIdentityKeyAgreementPriv,
            bobBundle: bobBundle
        )

        XCTAssertEqual(initiatorResult.usedOneTimePrekeyId, 42)

        // 3. Bob receives X3DH parameters and derives master key
        let bobDerivedKey = try X3DHEngine.shared.receiveSession(
            bobIdentityKey: bobIdentityKeyAgreementPriv,
            bobSignedPrekey: bobSignedPrekeyPriv,
            bobOneTimePrekey: bobOneTimePrekeyPriv,
            aliceIdentityPublicKey: aliceIdentityKeyAgreementPriv.publicKey,
            aliceEphemeralPublicKey: initiatorResult.ephemeralPublicKey
        )

        // 4. Verify Alice and Bob derived the exact identical 256-bit Master Shared Key
        let aliceKeyBytes = initiatorResult.masterSharedKey.withUnsafeBytes { Data($0) }
        let bobKeyBytes = bobDerivedKey.withUnsafeBytes { Data($0) }

        XCTAssertEqual(aliceKeyBytes, bobKeyBytes, "Alice and Bob must derive identical master keys via X3DH")
    }

    func testTamperedSignedPrekeySignatureThrows() throws {
        let bobIdentityKeyAgreementPriv = Curve25519.KeyAgreement.PrivateKey()
        let bobIdentitySigningPriv = Curve25519.Signing.PrivateKey()
        let bobSignedPrekeyPriv = Curve25519.KeyAgreement.PrivateKey()

        // Invalid signature
        let corruptSignature = Data(repeating: 0xEE, count: 64)

        let bobBundle = X3DHPrekeyBundle(
            identityAgreementPublicKey: bobIdentityKeyAgreementPriv.publicKey,
            identitySigningPublicKey: bobIdentitySigningPriv.publicKey,
            signedPrekeyPublicKey: bobSignedPrekeyPriv.publicKey,
            signedPrekeySignature: corruptSignature,
            signedPrekeyId: 1
        )

        let aliceIdentityKeyAgreementPriv = Curve25519.KeyAgreement.PrivateKey()

        XCTAssertThrowsError(
            try X3DHEngine.shared.initiateSession(
                aliceIdentityKey: aliceIdentityKeyAgreementPriv,
                bobBundle: bobBundle
            )
        ) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.invalidSignature)
        }
    }
}
