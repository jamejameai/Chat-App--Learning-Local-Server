import Foundation
import CryptoKit

public final class AttachmentManager: @unchecked Sendable {
    public static let shared = AttachmentManager()

    private let cacheDirectory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("DecryptedAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    public func uploadAttachment(
        fileData: Data,
        mimeType: String,
        fileName: String
    ) async throws -> MessageAttachment {
        // 1. Client-side AES-256-GCM encryption
        let encResult = try FileEncryptionService.shared.encrypt(fileData: fileData)

        // 2. Upload ciphertext to backend (Zero-Knowledge: server never sees plaintext or key)
        struct UploadBody: Codable {
            let data_base64: String
            let mime_type: String
            let sha256_checksum: String
        }

        struct UploadResponse: Codable {
            let id: String
            let byte_size: Int64
            let sha256_checksum: String
            let mime_type: String
            let download_url: String
        }

        let body = UploadBody(
            data_base64: encResult.ciphertext.base64EncodedString(),
            mime_type: mimeType,
            sha256_checksum: encResult.sha256Checksum
        )

        let res: UploadResponse = try await APIClient.shared.request(
            endpoint: "/attachments/upload",
            method: "POST",
            body: body,
            requiresAuth: true
        )

        // 3. Cache locally so sender doesn't need to re-download
        let localCachePath = cacheDirectory.appendingPathComponent(res.id).path
        try? fileData.write(to: URL(fileURLWithPath: localCachePath))

        return MessageAttachment(
            id: res.id,
            fileName: fileName,
            mimeType: mimeType,
            byteSize: res.byte_size,
            keyBase64: encResult.keyBase64,
            ivBase64: encResult.ivBase64,
            sha256Checksum: res.sha256_checksum,
            downloadUrl: res.download_url,
            localDecryptedPath: localCachePath
        )
    }

    public func uploadAttachment(
        fileURL: URL,
        fileName: String,
        mimeType: String
    ) async throws -> MessageAttachment {
        let data = try Data(contentsOf: fileURL)
        return try await uploadAttachment(fileData: data, mimeType: mimeType, fileName: fileName)
    }

    public func encryptAndUploadFile(
        fileURL: URL,
        fileName: String,
        mimeType: String
    ) async throws -> (id: String, keyBase64: String, ivBase64: String, sha256Checksum: String, downloadUrl: String) {
        let att = try await uploadAttachment(fileURL: fileURL, fileName: fileName, mimeType: mimeType)
        return (att.id, att.keyBase64, att.ivBase64, att.sha256Checksum, att.downloadUrl)
    }

    public func downloadAndDecrypt(attachment: MessageAttachment) async throws -> Data {
        // 1. Check local cache first
        let localFile = cacheDirectory.appendingPathComponent(attachment.id)
        if FileManager.default.fileExists(atPath: localFile.path),
           let cachedData = try? Data(contentsOf: localFile) {
            return cachedData
        }

        // 2. Fetch ciphertext from backend
        let endpoint = "/attachments/\(attachment.id)/download"
        let ciphertextData = try await APIClient.shared.requestRaw(
            endpoint: endpoint,
            method: "GET",
            requiresAuth: true
        )

        // 3. Verify SHA-256 integrity checksum
        let hash = SHA256.hash(data: ciphertextData)
        let computedChecksum = hash.compactMap { String(format: "%02x", $0) }.joined()
        guard computedChecksum.lowercased() == attachment.sha256Checksum.lowercased() else {
            throw CryptoError.invalidEnvelope
        }

        // 4. Decrypt with AES-256-GCM
        let decryptedData = try FileEncryptionService.shared.decrypt(
            ciphertext: ciphertextData,
            keyBase64: attachment.keyBase64,
            ivBase64: attachment.ivBase64
        )

        // 5. Store in local decrypted cache
        try? decryptedData.write(to: localFile)

        return decryptedData
    }

    public func downloadAndDecryptAttachment(attachment: MessageAttachment) async throws -> URL {
        let localFile = cacheDirectory.appendingPathComponent(attachment.id)
        if FileManager.default.fileExists(atPath: localFile.path) {
            return localFile
        }
        let decryptedData = try await downloadAndDecrypt(attachment: attachment)
        try decryptedData.write(to: localFile)
        return localFile
    }
}
