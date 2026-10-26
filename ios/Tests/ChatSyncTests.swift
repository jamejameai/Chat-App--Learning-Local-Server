import XCTest
@testable import MiniTelegram

final class ChatSyncTests: XCTestCase {

    private let conversationId = "chat-sync-tests-conversation"

    override func tearDown() {
        LocalDatabaseManager.shared.clearAll()
        super.tearDown()
    }

    // MARK: - FlexibleInt64 (server sends BIGINT sequence ids as strings)

    func testDecodesNumericStringFromServer() throws {
        struct Body: Decodable { let sequence_id: FlexibleInt64 }
        let body = try JSONDecoder().decode(Body.self, from: Data(#"{"sequence_id":"42"}"#.utf8))
        XCTAssertEqual(body.sequence_id.value, 42)
    }

    func testDecodesPlainNumber() throws {
        struct Body: Decodable { let sequence_id: FlexibleInt64 }
        let body = try JSONDecoder().decode(Body.self, from: Data(#"{"sequence_id":7}"#.utf8))
        XCTAssertEqual(body.sequence_id.value, 7)
    }

    func testRejectsNonNumericText() {
        struct Body: Decodable { let sequence_id: FlexibleInt64 }
        XCTAssertThrowsError(try JSONDecoder().decode(Body.self, from: Data(#"{"sequence_id":"abc"}"#.utf8)))
    }

    // MARK: - Sync cursor

    private func message(_ id: String, seq: Int64) -> ChatMessage {
        ChatMessage(
            id: id,
            conversationId: conversationId,
            senderUserId: "u1",
            senderName: "Alice",
            sequenceId: seq,
            text: "m\(seq)",
            status: .read,
            timestamp: Date(timeIntervalSince1970: Double(seq)),
            isOutgoing: false
        )
    }

    func testCursorIsZeroWhenNothingDownloaded() {
        XCTAssertEqual(LocalDatabaseManager.shared.latestStoredSequenceId(conversationId: conversationId), 0)
    }

    func testCursorIsHighestStoredMessageNotServerLatest() {
        // The chat list says the server's newest message is #9 ...
        LocalDatabaseManager.shared.saveConversations([
            ConversationItem(id: conversationId, title: "Alice", lastSequenceId: 9)
        ])
        // ... but only #1 and #2 have been downloaded to this phone.
        LocalDatabaseManager.shared.saveMessage(message("a", seq: 1))
        LocalDatabaseManager.shared.saveMessage(message("b", seq: 2))
        XCTAssertEqual(LocalDatabaseManager.shared.latestStoredSequenceId(conversationId: conversationId), 2,
                       "must resume after what we HAVE, otherwise messages 3...9 are skipped forever")
    }

    func testCursorAdvancesAsMessagesAreStored() {
        LocalDatabaseManager.shared.saveMessage(message("a", seq: 3))
        LocalDatabaseManager.shared.saveMessage(message("b", seq: 5))
        LocalDatabaseManager.shared.saveMessage(message("c", seq: 4))
        XCTAssertEqual(LocalDatabaseManager.shared.latestStoredSequenceId(conversationId: conversationId), 5)
    }
}
