import XCTest
import CryptoKit
@testable import MiniTelegram

final class CryptoIdentityTests: XCTestCase {

    func testDeviceKeyGenerationAndSignatureVerification() throws {
        let keys = try CryptoIdentityService.shared.generateInitialDeviceKeys(oneTimePrekeyCount: 10)

        // 1. Verify key properties
        XCTAssertFalse(keys.identityAgreementPublicKeyBase64.isEmpty)
        XCTAssertFalse(keys.identitySigningPublicKeyBase64.isEmpty)
        XCTAssertFalse(keys.signedPrekeyPublicKeyBase64.isEmpty)
        XCTAssertFalse(keys.signedPrekeySignatureBase64.isEmpty)
        XCTAssertEqual(keys.oneTimePrekeys.count, 10)

        // 2. Cryptographically verify the Ed25519 signature on the signed prekey
        guard let signedPrekeyData = Data(base64Encoded: keys.signedPrekeyPublicKeyBase64),
              let sigData = Data(base64Encoded: keys.signedPrekeySignatureBase64),
              let identitySignPubData = Data(base64Encoded: keys.identitySigningPublicKeyBase64) else {
            XCTFail("Base64 decoding failed")
            return
        }

        let identitySignPubKey = try Curve25519.Signing.PublicKey(rawRepresentation: identitySignPubData)
        let isValid = identitySignPubKey.isValidSignature(sigData, for: signedPrekeyData)
        XCTAssertTrue(isValid, "Signed prekey signature must verify against identity signing key")
    }

    func testIdentityFingerprintFormatting() {
        let service = CryptoIdentityService.shared
        let dummyData = Data(repeating: 0x42, count: 32)
        let formatted = service.formatFingerprint(data: dummyData)

        // Formatted fingerprint should be blocks of 5 digits separated by spaces
        let blocks = formatted.split(separator: " ")
        XCTAssertEqual(blocks.count, 7)
        for block in blocks {
            XCTAssertEqual(block.count, 5)
            XCTAssertNotNil(Int(block))
        }
    }
}
