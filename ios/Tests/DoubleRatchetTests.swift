import XCTest
import CryptoKit
@testable import MiniTelegram

final class DoubleRatchetTests: XCTestCase {

    func testAliceBobPingPongExchange() throws {
        // 1. Shared secret established (e.g. from X3DH)
        let masterSharedKey = SymmetricKey(size: .bits256)
        let bobDHKeyPair = Curve25519.KeyAgreement.PrivateKey()

        // 2. Initialize sessions
        let aliceSession = DoubleRatchetSession(
            sharedMasterKey: masterSharedKey,
            recipientDHPublicKey: bobDHKeyPair.publicKey
        )

        let bobSession = DoubleRatchetSession(
            sharedMasterKey: masterSharedKey,
            ownDHKeyPair: bobDHKeyPair
        )

        // 3. Alice -> Bob: Message 1
        let msg1Text = "Hello Bob! This is our first encrypted message."
        let env1 = try aliceSession.encrypt(plaintext: Data(msg1Text.utf8))
        let decrypted1 = try bobSession.decrypt(envelope: env1)
        XCTAssertEqual(String(data: decrypted1, encoding: .utf8), msg1Text)

        // 4. Bob -> Alice: Message 2
        let msg2Text = "Hey Alice! The Double Ratchet protocol is working smoothly."
        let env2 = try bobSession.encrypt(plaintext: Data(msg2Text.utf8))
        let decrypted2 = try aliceSession.decrypt(envelope: env2)
        XCTAssertEqual(String(data: decrypted2, encoding: .utf8), msg2Text)

        // 5. Alice -> Bob: Message 3
        let msg3Text = "Forward secrecy and break-in recovery confirmed!"
        let env3 = try aliceSession.encrypt(plaintext: Data(msg3Text.utf8))
        let decrypted3 = try bobSession.decrypt(envelope: env3)
        XCTAssertEqual(String(data: decrypted3, encoding: .utf8), msg3Text)
    }

    func testBurstMessaging() throws {
        let masterSharedKey = SymmetricKey(size: .bits256)
        let bobDHKeyPair = Curve25519.KeyAgreement.PrivateKey()

        let aliceSession = DoubleRatchetSession(
            sharedMasterKey: masterSharedKey,
            recipientDHPublicKey: bobDHKeyPair.publicKey
        )

        let bobSession = DoubleRatchetSession(
            sharedMasterKey: masterSharedKey,
            ownDHKeyPair: bobDHKeyPair
        )

        // Alice sends 5 messages without any reply from Bob
        var envelopes: [RatchetMessageEnvelope] = []
        for i in 1...5 {
            let env = try aliceSession.encrypt(plaintext: Data("Burst message \(i)".utf8))
            envelopes.append(env)
        }

        // Bob decrypts all 5 in sequence
        for (index, env) in envelopes.enumerated() {
            let decrypted = try bobSession.decrypt(envelope: env)
            XCTAssertEqual(String(data: decrypted, encoding: .utf8), "Burst message \(index + 1)")
        }
    }

    func testOutOfOrderMessageDelivery() throws {
        let masterSharedKey = SymmetricKey(size: .bits256)
        let bobDHKeyPair = Curve25519.KeyAgreement.PrivateKey()

        let aliceSession = DoubleRatchetSession(
            sharedMasterKey: masterSharedKey,
            recipientDHPublicKey: bobDHKeyPair.publicKey
        )

        let bobSession = DoubleRatchetSession(
            sharedMasterKey: masterSharedKey,
            ownDHKeyPair: bobDHKeyPair
        )

        // Alice produces Message 1, 2, 3
        let env1 = try aliceSession.encrypt(plaintext: Data("Message 1".utf8))
        let env2 = try aliceSession.encrypt(plaintext: Data("Message 2".utf8))
        let env3 = try aliceSession.encrypt(plaintext: Data("Message 3".utf8))

        // Bob receives Message 3 first! (Skipped keys engine must cache keys for msg 1 and 2)
        let dec3 = try bobSession.decrypt(envelope: env3)
        XCTAssertEqual(String(data: dec3, encoding: .utf8), "Message 3")

        // Then Bob receives Message 1
        let dec1 = try bobSession.decrypt(envelope: env1)
        XCTAssertEqual(String(data: dec1, encoding: .utf8), "Message 1")

        // Then Bob receives Message 2
        let dec2 = try bobSession.decrypt(envelope: env2)
        XCTAssertEqual(String(data: dec2, encoding: .utf8), "Message 2")
    }

    func testTamperedCiphertextRejection() throws {
        let masterSharedKey = SymmetricKey(size: .bits256)
        let bobDHKeyPair = Curve25519.KeyAgreement.PrivateKey()

        let aliceSession = DoubleRatchetSession(
            sharedMasterKey: masterSharedKey,
            recipientDHPublicKey: bobDHKeyPair.publicKey
        )

        let bobSession = DoubleRatchetSession(
            sharedMasterKey: masterSharedKey,
            ownDHKeyPair: bobDHKeyPair
        )

        let env = try aliceSession.encrypt(plaintext: Data("Secret message".utf8))

        // Tamper with ciphertext by corrupting bytes
        guard var rawCipherData = Data(base64Encoded: env.ciphertextBase64) else {
            XCTFail("Failed to decode ciphertext")
            return
        }
        rawCipherData[rawCipherData.count / 2] ^= 0xFF

        let tamperedEnv = RatchetMessageEnvelope(
            dhPublicKeyBase64: env.dhPublicKeyBase64,
            messageNumber: env.messageNumber,
            previousChainLength: env.previousChainLength,
            ciphertextBase64: rawCipherData.base64EncodedString(),
            nonceBase64: env.nonceBase64
        )

        XCTAssertThrowsError(try bobSession.decrypt(envelope: tamperedEnv)) { error in
            // Must fail AEAD integrity check
            XCTAssertTrue(error is CryptoError || error is CryptoKitError)
        }
    }
}
