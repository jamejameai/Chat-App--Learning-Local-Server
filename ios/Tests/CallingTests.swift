import XCTest
import CryptoKit
@testable import MiniTelegram

final class CallingTests: XCTestCase {

    func testCallModelsAndCodable() throws {
        let call = CallItem(
            id: "call-12345",
            conversationId: "conv-999",
            conversationTitle: "Core Team",
            callerUserId: "user-1",
            callerName: "Alice",
            callType: .video,
            status: "dialing",
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: 125,
            isOutgoing: true,
            livekitRoomName: "room_test123",
            token: "jwt.test.token"
        )

        let data = try JSONEncoder().encode(call)
        let decoded = try JSONDecoder().decode(CallItem.self, from: data)

        XCTAssertEqual(decoded.id, call.id)
        XCTAssertEqual(decoded.conversationId, call.conversationId)
        XCTAssertEqual(decoded.conversationTitle, "Core Team")
        XCTAssertEqual(decoded.callType, .video)
        XCTAssertEqual(decoded.durationSeconds, 125)
        XCTAssertTrue(decoded.isOutgoing)
        XCTAssertEqual(decoded.livekitRoomName, "room_test123")
    }

    func testFrameCryptorKeyDerivationAndFingerprintDeterminism() {
        let sharedSecret = SymmetricKey(size: .bits256)
        let callId = "call-sec-777"

        let callKey1 = FrameCryptorManager.shared.deriveCallKey(sharedSecret: sharedSecret, callId: callId)
        let callKey2 = FrameCryptorManager.shared.deriveCallKey(sharedSecret: sharedSecret, callId: callId)

        // Keys derived from same inputs must match
        XCTAssertEqual(
            callKey1.withUnsafeBytes { Data($0) },
            callKey2.withUnsafeBytes { Data($0) }
        )

        // Verification fingerprints must be deterministic
        let fp1 = FrameCryptorManager.shared.computeVerificationFingerprint(key: callKey1)
        let fp2 = FrameCryptorManager.shared.computeVerificationFingerprint(key: callKey2)
        XCTAssertEqual(fp1, fp2)

        let emojis = fp1.components(separatedBy: " ")
        XCTAssertEqual(emojis.count, 4, "Verification fingerprint must consist of 4 emojis")
        for emoji in emojis {
            XCTAssertFalse(emoji.isEmpty)
        }

        // Different call key must produce distinct fingerprint
        let differentKey = SymmetricKey(size: .bits256)
        let differentFp = FrameCryptorManager.shared.computeVerificationFingerprint(key: differentKey)
        XCTAssertNotEqual(fp1, differentFp)
    }

    func testFrameCryptorEncryptDecryptMediaFrame() throws {
        let key = SymmetricKey(size: .bits256)
        let frameIndex: UInt64 = 1001

        // Synthetic 256-byte WebRTC media frame
        var rawFrame = [UInt8](repeating: 0, count: 256)
        _ = SecRandomCopyBytes(kSecRandomDefault, rawFrame.count, &rawFrame)
        let originalData = Data(rawFrame)

        // Encrypt frame with SFrame AES-GCM
        let encryptedFrame = try FrameCryptorManager.shared.encryptFrame(
            rawFrame: originalData,
            key: key,
            frameIndex: frameIndex
        )

        XCTAssertNotEqual(encryptedFrame, originalData)
        XCTAssertEqual(encryptedFrame.count, originalData.count + 16, "Ciphertext must include 16-byte GCM tag")

        // Decrypt with correct key and frame index
        let decryptedData = try FrameCryptorManager.shared.decryptFrame(
            encryptedFrame: encryptedFrame,
            key: key,
            frameIndex: frameIndex
        )

        XCTAssertEqual(decryptedData, originalData, "Decrypted frame must match raw frame exactly")

        // Tampered frame index must fail decryption
        XCTAssertThrowsError(
            try FrameCryptorManager.shared.decryptFrame(
                encryptedFrame: encryptedFrame,
                key: key,
                frameIndex: frameIndex + 1
            )
        )
    }

    @MainActor
    func testCallStateSequence() {
        let manager = CallManager.shared
        XCTAssertEqual(manager.callState, .idle)
        XCTAssertFalse(manager.isMuted)
        XCTAssertTrue(manager.isSpeakerOn)

        manager.toggleMute()
        XCTAssertTrue(manager.isMuted)
        manager.toggleMute()
        XCTAssertFalse(manager.isMuted)

        manager.toggleVideo()
        XCTAssertTrue(manager.isVideoEnabled)
        manager.toggleVideo()
        XCTAssertFalse(manager.isVideoEnabled)
    }
}
