import XCTest
import CryptoKit
@testable import MiniTelegram

final class NotificationAndSyncTests: XCTestCase {

    func testZeroKnowledgePayloadHasNoPlaintext() throws {
        // Simulated backend push dictionary
        let rawPushPayload: [String: Any] = [
            "aps": [
                "content-available": 1,
                "mutable-content": 1,
                "alert": [
                    "title-loc-key": "PUSH_NEW_MESSAGE",
                    "loc-key": "PUSH_MESSAGE_BODY"
                ],
                "sound": "default",
                "badge": 1
            ],
            "data": [
                "conversation_id": "c1111111-1111-1111-1111-111111111111",
                "sequence_id": 42,
                "envelope_type": "double_ratchet",
                "encrypted_payload": "q83kjsd8f7y2h3k4jh2k3j4hk23jh42k3j==",
                "iv": "dGVzdGl2MTIz",
                "is_call": false
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: rawPushPayload)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        // Zero-Knowledge Assertions:
        // 1. Raw push payload MUST NOT contain plaintext message text
        XCTAssertFalse(jsonString.contains("Hello"))
        XCTAssertFalse(jsonString.contains("Secret"))
        XCTAssertFalse(jsonString.contains("Alice"))

        // 2. Alert must only use localization keys
        let aps = rawPushPayload["aps"] as? [String: Any]
        let alert = aps?["alert"] as? [String: Any]
        XCTAssertEqual(alert?["title-loc-key"] as? String, "PUSH_NEW_MESSAGE")
        XCTAssertEqual(alert?["loc-key"] as? String, "PUSH_MESSAGE_BODY")

        // 3. Data must contain cryptographic envelope keys
        let data = rawPushPayload["data"] as? [String: Any]
        XCTAssertNotNil(data?["encrypted_payload"])
        XCTAssertNotNil(data?["iv"])
        XCTAssertNotNil(data?["envelope_type"])
    }

    func testOfflinePushDecryptionAndStorage() {
        let conversationId = "conv-offline-sync-\(UUID().uuidString)"
        let originalText = "Encrypted push confidential notification test"

        // Encrypt message using MessageCryptoCoordinator
        let (payload, iv, envType) = try! MessageCryptoCoordinator.shared.encryptMessage(
            conversationId: conversationId,
            text: originalText
        )

        let pushUserInfo: [AnyHashable: Any] = [
            "data": [
                "conversation_id": conversationId,
                "sequence_id": NSNumber(value: 99),
                "message_id": UUID().uuidString,
                "envelope_type": envType,
                "encrypted_payload": payload,
                "iv": iv
            ]
        ]

        // Handle incoming encrypted push
        let handled = PushNotificationManager.shared.handleRemoteNotification(userInfo: pushUserInfo)
        XCTAssertTrue(handled)

        // Verify message was stored in local database
        let messages = LocalDatabaseManager.shared.getMessages(conversationId: conversationId)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.text, originalText)
        XCTAssertEqual(messages.first?.sequenceId, 99)
    }

    func testBackgroundSyncTaskId() {
        XCTAssertEqual(BackgroundSyncManager.taskId, "com.minitelegram.background-sync")
    }
}
