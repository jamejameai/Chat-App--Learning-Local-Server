import XCTest
import CryptoKit
@testable import MiniTelegram

final class GroupAndAttachmentTests: XCTestCase {

    func testGroupMemberRoles() {
        let owner = GroupMember(
            id: "user-1",
            username: "alice",
            displayName: "Alice",
            avatarUrl: nil,
            role: "owner",
            joinedAt: nil
        )
        XCTAssertTrue(owner.isOwner)
        XCTAssertTrue(owner.isAdmin)
        XCTAssertEqual(owner.title, "Alice")

        let admin = GroupMember(
            id: "user-2",
            username: "bob",
            displayName: "Bob",
            avatarUrl: nil,
            role: "admin",
            joinedAt: nil
        )
        XCTAssertFalse(admin.isOwner)
        XCTAssertTrue(admin.isAdmin)

        let member = GroupMember(
            id: "user-3",
            username: "charlie",
            displayName: nil,
            avatarUrl: nil,
            role: "member",
            joinedAt: nil
        )
        XCTAssertFalse(member.isOwner)
        XCTAssertFalse(member.isAdmin)
        XCTAssertEqual(member.title, "charlie")

        let readOnly = GroupMember(
            id: "user-4",
            username: "dave",
            displayName: "Dave",
            avatarUrl: nil,
            role: "read_only",
            joinedAt: nil
        )
        XCTAssertFalse(readOnly.isOwner)
        XCTAssertFalse(readOnly.isAdmin)
    }

    func testAttachmentMetadataCodable() throws {
        let attachment = MessageAttachment(
            id: "att-123",
            fileName: "project_roadmap.pdf",
            mimeType: "application/pdf",
            byteSize: 1048576,
            keyBase64: "a2V5MTIz",
            ivBase64: "aXYxMjM=",
            sha256Checksum: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            downloadUrl: "https://example.com/files/att-123.enc",
            localDecryptedPath: "/path/to/local.pdf"
        )

        let data = try JSONEncoder().encode(attachment)
        let decoded = try JSONDecoder().decode(MessageAttachment.self, from: data)

        XCTAssertEqual(decoded.id, attachment.id)
        XCTAssertEqual(decoded.fileName, "project_roadmap.pdf")
        XCTAssertEqual(decoded.mimeType, "application/pdf")
        XCTAssertEqual(decoded.byteSize, 1048576)
        XCTAssertEqual(decoded.keyBase64, "a2V5MTIz")
        XCTAssertEqual(decoded.sha256Checksum, attachment.sha256Checksum)
    }

    func testVoiceNoteMetadataCodable() throws {
        let waveform: [Float] = [0.1, 0.4, 0.8, 0.95, 0.6, 0.3, 0.2]
        let voiceNote = VoiceNoteMetadata(
            durationSeconds: 14.5,
            waveformSamples: waveform
        )

        let data = try JSONEncoder().encode(voiceNote)
        let decoded = try JSONDecoder().decode(VoiceNoteMetadata.self, from: data)

        XCTAssertEqual(decoded.durationSeconds, 14.5)
        XCTAssertEqual(decoded.waveformSamples.count, waveform.count)
        XCTAssertEqual(decoded.waveformSamples[3], 0.95, accuracy: 0.001)
    }

    func testAttachmentZeroKnowledgeFileEncryption() throws {
        // Create 64KB random plaintext payload
        var randomBytes = [UInt8](repeating: 0, count: 65536)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        let originalData = Data(randomBytes)

        let tempDir = FileManager.default.temporaryDirectory
        let inputURL = tempDir.appendingPathComponent("test_in_\(UUID().uuidString).bin")
        try originalData.write(to: inputURL)
        defer { try? FileManager.default.removeItem(at: inputURL) }

        // Encrypt with FileEncryptionService
        let (encryptedURL, key, iv, sha256) = try FileEncryptionService.encryptFile(at: inputURL)
        defer { try? FileManager.default.removeItem(at: encryptedURL) }

        // Verify encrypted file exists and differs from original
        let encryptedData = try Data(contentsOf: encryptedURL)
        XCTAssertNotEqual(encryptedData, originalData)

        // Decrypt with key and iv
        let decryptedURL = try FileEncryptionService.decryptFile(at: encryptedURL, key: key, iv: iv)
        defer { try? FileManager.default.removeItem(at: decryptedURL) }

        let decryptedData = try Data(contentsOf: decryptedURL)
        XCTAssertEqual(decryptedData, originalData)

        // Verify SHA-256 ciphertext integrity
        let ciphertextSha256 = SHA256.hash(data: encryptedData)
        let computedHex = ciphertextSha256.compactMap { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(computedHex, sha256)
    }

    func testCoordinatorGroupVoiceNoteEncryptionAndDecryption() throws {
        let conversationId = "group-test-456"
        let groupSession = SenderKeySession(
            groupId: conversationId,
            senderUserId: "alice-id",
            senderDeviceId: "alice-phone"
        )

        // Register session on coordinator
        MessageCryptoCoordinator.shared.registerGroupSession(conversationId: conversationId, session: groupSession)

        let voiceNote = VoiceNoteMetadata(durationSeconds: 7.2, waveformSamples: [0.2, 0.5, 0.7, 0.4])
        let attachment = MessageAttachment(
            fileName: "voice.m4a",
            mimeType: "audio/m4a",
            byteSize: 32000,
            keyBase64: "dGVzdGtleQ==",
            ivBase64: "dGVzdGl2",
            sha256Checksum: "abcd1234",
            downloadUrl: "https://example.com/voice.m4a.enc"
        )

        // Encrypt as group message
        let (payload, iv, envType) = try MessageCryptoCoordinator.shared.encryptMessage(
            conversationId: conversationId,
            text: "Listen to this update",
            replyToMessageId: nil,
            attachment: attachment,
            voiceNote: voiceNote,
            isGroup: true,
            senderUserId: "alice-id",
            senderDeviceId: "alice-phone"
        )

        XCTAssertEqual(envType, "sender_key")
        XCTAssertFalse(payload.isEmpty)

        // Decrypt using coordinator
        let decrypted = MessageCryptoCoordinator.shared.decryptMessage(
            conversationId: conversationId,
            encryptedPayloadBase64: payload,
            ivBase64: iv,
            envelopeType: envType
        )

        XCTAssertEqual(decrypted.text, "Listen to this update")
        XCTAssertNotNil(decrypted.voiceNote)
        XCTAssertEqual(decrypted.voiceNote?.durationSeconds, 7.2)
        XCTAssertEqual(decrypted.voiceNote?.waveformSamples.count, 4)
        XCTAssertEqual(decrypted.attachment?.fileName, "voice.m4a")
        XCTAssertEqual(decrypted.attachment?.byteSize, 32000)
    }

    func testCoordinatorRotateGroupSenderKey() {
        let conversationId = "group-rotation-test"
        let initialSession = SenderKeySession(
            groupId: conversationId,
            senderUserId: "user-1",
            senderDeviceId: "dev-1"
        )
        MessageCryptoCoordinator.shared.registerGroupSession(conversationId: conversationId, session: initialSession)

        // Trigger rotation upon member eviction
        MessageCryptoCoordinator.shared.rotateGroupSenderKey(
            conversationId: conversationId,
            senderUserId: "user-1",
            senderDeviceId: "dev-1"
        )

        // Should not crash and should allow further encryption
        XCTAssertNoThrow(
            try MessageCryptoCoordinator.shared.encryptMessage(
                conversationId: conversationId,
                text: "Post-eviction message",
                isGroup: true,
                senderUserId: "user-1",
                senderDeviceId: "dev-1"
            )
        )
    }
}
