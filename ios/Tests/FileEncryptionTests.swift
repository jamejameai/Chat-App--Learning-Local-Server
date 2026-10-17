import XCTest
import CryptoKit
@testable import MiniTelegram

final class FileEncryptionTests: XCTestCase {

    func testEncryptAndDecryptFile() throws {
        let service = FileEncryptionService.shared

        // Generate synthetic binary payload (e.g. simulated photo/voice audio)
        let originalPayload = Data((0..<1024).map { UInt8($0 % 256) })
        let filename = "voice_memo_001.m4a"
        let mimeType = "audio/mp4"

        // 1. Encrypt on client
        let package = try service.encryptFile(
            fileData: originalPayload,
            filename: filename,
            mimeType: mimeType
        )

        // 2. Verify ciphertext properties
        XCTAssertNotEqual(package.ciphertext, originalPayload)
        XCTAssertEqual(package.metadata.originalFilename, filename)
        XCTAssertEqual(package.metadata.mimeType, mimeType)
        XCTAssertEqual(package.metadata.byteSize, originalPayload.count)
        XCTAssertFalse(package.metadata.sha256Hex.isEmpty)
        XCTAssertFalse(package.metadata.keyBase64.isEmpty)

        // 3. Decrypt on recipient client
        let decrypted = try service.decryptFile(
            ciphertext: package.ciphertext,
            metadata: package.metadata
        )

        XCTAssertEqual(decrypted, originalPayload, "Decrypted file must match original payload bit-for-bit")
    }

    func testTamperedCiphertextChecksumFails() throws {
        let service = FileEncryptionService.shared
        let originalPayload = Data("Protected confidential document".utf8)

        let package = try service.encryptFile(
            fileData: originalPayload,
            filename: "doc.pdf",
            mimeType: "application/pdf"
        )

        // Corrupt 1 byte in ciphertext
        var corruptCiphertext = package.ciphertext
        corruptCiphertext[corruptCiphertext.count / 2] ^= 0xAA

        XCTAssertThrowsError(
            try service.decryptFile(
                ciphertext: corruptCiphertext,
                metadata: package.metadata
            )
        ) { error in
            XCTAssertEqual(error as? CryptoError, CryptoError.decryptionFailed)
        }
    }
}
