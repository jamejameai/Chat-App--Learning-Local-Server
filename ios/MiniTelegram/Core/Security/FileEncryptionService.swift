import Foundation
import CryptoKit

public struct EncryptedFileMetadata: Codable, Sendable {
    public let keyBase64: String
    public let ivBase64: String
    public let sha256Hex: String
    public let mimeType: String
    public let originalFilename: String
    public let byteSize: Int

    public init(
        keyBase64: String,
        ivBase64: String,
        sha256Hex: String,
        mimeType: String,
        originalFilename: String,
        byteSize: Int
    ) {
        self.keyBase64 = keyBase64
        self.ivBase64 = ivBase64
        self.sha256Hex = sha256Hex
        self.mimeType = mimeType
        self.originalFilename = originalFilename
        self.byteSize = byteSize
    }
}

public struct EncryptedFilePackage: Sendable {
    public let ciphertext: Data
    public let metadata: EncryptedFileMetadata
}

public final class FileEncryptionService: Sendable {
    public static let shared = FileEncryptionService()

    private init() {}

    public func encryptFile(
        fileData: Data,
        filename: String,
        mimeType: String
    ) throws -> EncryptedFilePackage {
        // 1. Generate cryptographically random 256-bit symmetric key
        let key = SymmetricKey(size: .bits256)
        let nonce = AES.GCM.Nonce()

        // 2. Encrypt plaintext bytes with AES-GCM
        let sealedBox = try AES.GCM.seal(fileData, using: key, nonce: nonce)
        let ciphertext = sealedBox.ciphertext + sealedBox.tag

        // 3. Compute SHA-256 checksum of the ciphertext
        let digest = SHA256.hash(data: ciphertext)
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

        let keyBase64 = key.withUnsafeBytes { Data($0).base64EncodedString() }
        let ivBase64 = Data(nonce).base64EncodedString()

        let metadata = EncryptedFileMetadata(
            keyBase64: keyBase64,
            ivBase64: ivBase64,
            sha256Hex: sha256Hex,
            mimeType: mimeType,
            originalFilename: filename,
            byteSize: fileData.count
        )

        return EncryptedFilePackage(ciphertext: ciphertext, metadata: metadata)
    }

    public func decryptFile(
        ciphertext: Data,
        metadata: EncryptedFileMetadata
    ) throws -> Data {
        // 1. Verify SHA-256 checksum of ciphertext
        let digest = SHA256.hash(data: ciphertext)
        let actualSha256Hex = digest.map { String(format: "%02x", $0) }.joined()
        guard actualSha256Hex.lowercased() == metadata.sha256Hex.lowercased() else {
            throw CryptoError.decryptionFailed
        }

        // 2. Parse key and nonce
        guard let keyData = Data(base64Encoded: metadata.keyBase64),
              let nonceData = Data(base64Encoded: metadata.ivBase64),
              let nonce = try? AES.GCM.Nonce(data: nonceData) else {
            throw CryptoError.invalidEnvelope
        }

        guard ciphertext.count >= 16 else {
            throw CryptoError.decryptionFailed
        }

        let tag = ciphertext.suffix(16)
        let rawCiphertext = ciphertext.dropLast(16)
        let key = SymmetricKey(data: keyData)

        // 3. Decrypt with AES-GCM
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: rawCiphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    public func encrypt(fileData: Data) throws -> (ciphertext: Data, keyBase64: String, ivBase64: String, sha256Checksum: String) {
        let package = try encryptFile(fileData: fileData, filename: "file.bin", mimeType: "application/octet-stream")
        return (
            ciphertext: package.ciphertext,
            keyBase64: package.metadata.keyBase64,
            ivBase64: package.metadata.ivBase64,
            sha256Checksum: package.metadata.sha256Hex
        )
    }

    public func decrypt(ciphertext: Data, keyBase64: String, ivBase64: String) throws -> Data {
        let digest = SHA256.hash(data: ciphertext)
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()
        let metadata = EncryptedFileMetadata(
            keyBase64: keyBase64,
            ivBase64: ivBase64,
            sha256Hex: sha256Hex,
            mimeType: "application/octet-stream",
            originalFilename: "file.bin",
            byteSize: 0
        )
        return try decryptFile(ciphertext: ciphertext, metadata: metadata)
    }

    public static func encryptFile(at fileURL: URL) throws -> (encryptedURL: URL, key: Data, iv: Data, sha256: String) {
        let plaintext = try Data(contentsOf: fileURL)
        let package = try shared.encryptFile(fileData: plaintext, filename: fileURL.lastPathComponent, mimeType: "application/octet-stream")
        let tempEncrypted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".enc")
        try package.ciphertext.write(to: tempEncrypted)
        let keyData = Data(base64Encoded: package.metadata.keyBase64)!
        let ivData = Data(base64Encoded: package.metadata.ivBase64)!
        return (tempEncrypted, keyData, ivData, package.metadata.sha256Hex)
    }

    public static func decryptFile(at fileURL: URL, key: Data, iv: Data) throws -> URL {
        let ciphertext = try Data(contentsOf: fileURL)
        let decryptedData = try shared.decrypt(
            ciphertext: ciphertext,
            keyBase64: key.base64EncodedString(),
            ivBase64: iv.base64EncodedString()
        )
        let tempDecrypted = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dec")
        try decryptedData.write(to: tempDecrypted)
        return tempDecrypted
    }
}
