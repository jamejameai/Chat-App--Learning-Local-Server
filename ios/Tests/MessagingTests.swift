import XCTest
import CryptoKit
@testable import MiniTelegram

final class MessagingTests: XCTestCase {
    private var tempDir: URL!
    private var db: LocalDatabaseManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = LocalDatabaseManager(customStorageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testMessageInsertionAndSorting() {
        let convId = "conv-1"
        let conv = ConversationItem(id: convId, title: "Alice")
        db.saveConversation(conv)

        // Insert out of sequence order
        let msg2 = ChatMessage(id: "msg-2", conversationId: convId, senderUserId: "u-2", senderName: "Alice", sequenceId: 2, text: "Second message", timestamp: Date().addingTimeInterval(1))
        let msg1 = ChatMessage(id: "msg-1", conversationId: convId, senderUserId: "u-2", senderName: "Alice", sequenceId: 1, text: "First message", timestamp: Date())
        let msg3 = ChatMessage(id: "msg-3", conversationId: convId, senderUserId: "u-2", senderName: "Alice", sequenceId: 3, text: "Third message", timestamp: Date().addingTimeInterval(2))

        db.saveMessage(msg2)
        db.saveMessage(msg1)
        db.saveMessage(msg3)

        let loaded = db.getMessages(conversationId: convId)
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded[0].sequenceId, 1)
        XCTAssertEqual(loaded[1].sequenceId, 2)
        XCTAssertEqual(loaded[2].sequenceId, 3)
    }

    func testMessageIdempotencyDeduplication() {
        let convId = "conv-2"
        let conv = ConversationItem(id: convId, title: "Engineering")
        db.saveConversation(conv)

        let msg = ChatMessage(id: "msg-dedup-1", conversationId: convId, senderUserId: "u-1", senderName: "Bob", sequenceId: 10, text: "Initial text", status: .sending)
        db.saveMessage(msg)

        var loaded = db.getMessages(conversationId: convId)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].status, .sending)

        // Re-saving same message with updated status
        var updatedMsg = msg
        updatedMsg.status = .sent
        db.saveMessage(updatedMsg)

        loaded = db.getMessages(conversationId: convId)
        XCTAssertEqual(loaded.count, 1, "Must deduplicate and update existing message without creating duplicate")
        XCTAssertEqual(loaded[0].status, .sent)
    }

    func testLocalFullTextSearch() {
        let convId = "conv-3"
        let conv = ConversationItem(id: convId, title: "Security Team")
        db.saveConversation(conv)

        let msg1 = ChatMessage(id: "m1", conversationId: convId, senderUserId: "u-1", senderName: "Bob", text: "Please review the cryptographic Double Ratchet protocol")
        let msg2 = ChatMessage(id: "m2", conversationId: convId, senderUserId: "u-2", senderName: "Alice", text: "Database migrations for PostgreSQL 16 are complete")
        let msg3 = ChatMessage(id: "m3", conversationId: convId, senderUserId: "u-1", senderName: "Bob", text: "WebRTC SFU call relay is operational")

        db.saveMessage(msg1)
        db.saveMessage(msg2)
        db.saveMessage(msg3)

        let searchRatchet = db.searchMessages(query: "ratchet")
        XCTAssertEqual(searchRatchet.count, 1)
        XCTAssertEqual(searchRatchet.first?.id, "m1")

        let searchPostgres = db.searchMessages(query: "PostgreSQL")
        XCTAssertEqual(searchPostgres.count, 1)
        XCTAssertEqual(searchPostgres.first?.id, "m2")

        let searchNonExistent = db.searchMessages(query: "UnicornXYZ")
        XCTAssertEqual(searchNonExistent.count, 0)
    }

    func testReactionToggling() {
        let convId = "conv-4"
        let msg = ChatMessage(id: "m-react", conversationId: convId, senderUserId: "u-1", senderName: "Alice", text: "Ship date confirmed!")
        db.saveMessage(msg)

        // 1. User 1 reacts with ❤️
        db.toggleReaction(messageId: "m-react", conversationId: convId, emoji: "❤️", userId: "u-1")
        var loaded = db.getMessages(conversationId: convId).first!
        XCTAssertEqual(loaded.reactions.count, 1)
        XCTAssertEqual(loaded.reactions[0].emoji, "❤️")
        XCTAssertEqual(loaded.reactions[0].count, 1)

        // 2. User 2 reacts with ❤️
        db.toggleReaction(messageId: "m-react", conversationId: convId, emoji: "❤️", userId: "u-2")
        loaded = db.getMessages(conversationId: convId).first!
        XCTAssertEqual(loaded.reactions[0].count, 2)

        // 3. User 1 toggles off ❤️
        db.toggleReaction(messageId: "m-react", conversationId: convId, emoji: "❤️", userId: "u-1")
        loaded = db.getMessages(conversationId: convId).first!
        XCTAssertEqual(loaded.reactions[0].count, 1)

        // 4. User 2 toggles off ❤️
        db.toggleReaction(messageId: "m-react", conversationId: convId, emoji: "❤️", userId: "u-2")
        loaded = db.getMessages(conversationId: convId).first!
        XCTAssertTrue(loaded.reactions.isEmpty, "Reaction list should be empty after all reactions toggled off")
    }

    func testReadReceiptsAndUnreadCount() {
        let convId = "conv-5"
        var conv = ConversationItem(id: convId, title: "General", unreadCount: 0)
        db.saveConversation(conv)

        // Incoming message arrives
        let incoming = ChatMessage(id: "m-inc", conversationId: convId, senderUserId: "u-peer", senderName: "Peer", text: "Hey! Any updates?", status: .delivered, isOutgoing: false)
        db.saveMessage(incoming)

        conv = db.getConversation(byId: convId)!
        XCTAssertEqual(conv.unreadCount, 1)

        // Mark read
        db.markConversationRead(conversationId: convId)

        conv = db.getConversation(byId: convId)!
        XCTAssertEqual(conv.unreadCount, 0)

        let loadedMsg = db.getMessages(conversationId: convId).first!
        XCTAssertEqual(loadedMsg.status, .read)
    }

    func testMessageCryptoCoordinatorRoundTrip() throws {
        let coordinator = MessageCryptoCoordinator.shared

        let plainText = "Confidential project update: Zero-Trust verified."
        let (payload, iv, envelopeType) = try coordinator.encryptMessage(
            conversationId: "conv-crypto-test",
            text: plainText,
            replyToMessageId: "ref-msg-123"
        )

        XCTAssertFalse(payload.isEmpty)
        XCTAssertFalse(iv.isEmpty)
        XCTAssertEqual(envelopeType, "double_ratchet")
    }
}
