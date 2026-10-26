import XCTest
@testable import MiniTelegram

final class SeenStatusTests: XCTestCase {

    private let conv = "seen-status-tests"
    private let db = LocalDatabaseManager.shared

    override func tearDown() {
        db.clearAll()
        SessionStore.clear()
        super.tearDown()
    }

    private func message(_ id: String, seq: Int64, outgoing: Bool, status: MessageDeliveryStatus) -> ChatMessage {
        ChatMessage(
            id: id,
            conversationId: conv,
            senderUserId: outgoing ? "me" : "friend",
            senderName: outgoing ? "Me" : "Friend",
            sequenceId: seq,
            text: "m\(seq)",
            status: status,
            timestamp: Date(timeIntervalSince1970: Double(seq)),
            isOutgoing: outgoing
        )
    }

    private func status(_ id: String) -> MessageDeliveryStatus? {
        db.getMessages(conversationId: conv).first { $0.id == id }?.status
    }

    func testSeenNeverGoesBackToSentWhenResynced() {
        db.saveMessage(message("a", seq: 1, outgoing: true, status: .read))
        db.saveMessage(message("a", seq: 1, outgoing: true, status: .sent)) // e.g. a later sync
        XCTAssertEqual(status("a"), .read)
    }

    func testStatusStillMovesForward() {
        db.saveMessage(message("a", seq: 0, outgoing: true, status: .sending))
        db.saveMessage(message("a", seq: 1, outgoing: true, status: .sent))
        XCTAssertEqual(status("a"), .sent)
        db.saveMessage(message("b", seq: 0, outgoing: true, status: .failed))
        db.saveMessage(message("b", seq: 0, outgoing: true, status: .sending)) // retry
        XCTAssertEqual(status("b"), .sending)
    }

    func testReadReceiptMarksMyMessagesUpToThatPointAsSeen() {
        db.saveMessage(message("a", seq: 1, outgoing: true, status: .sent))
        db.saveMessage(message("b", seq: 2, outgoing: true, status: .sent))
        db.saveMessage(message("c", seq: 3, outgoing: true, status: .sent))
        db.saveMessage(message("in", seq: 2, outgoing: false, status: .delivered))

        XCTAssertTrue(db.markOutgoingRead(conversationId: conv, upToSequence: 2))

        XCTAssertEqual(status("a"), .read)
        XCTAssertEqual(status("b"), .read)
        XCTAssertEqual(status("c"), .sent, "not seen yet")
        XCTAssertEqual(status("in"), .delivered, "incoming messages are not touched")
        XCTAssertFalse(db.markOutgoingRead(conversationId: conv, upToSequence: 2), "nothing left to change")
    }

    func testHasMessage() {
        db.saveMessage(message("a", seq: 1, outgoing: false, status: .delivered))
        XCTAssertTrue(db.hasMessage(id: "a", conversationId: conv))
        XCTAssertFalse(db.hasMessage(id: "zzz", conversationId: conv))
    }

    func testTotalUnreadCountForBadge() {
        db.saveConversations([ConversationItem(id: conv, title: "Friend")])
        db.saveMessage(message("a", seq: 1, outgoing: false, status: .delivered))
        db.saveMessage(message("b", seq: 2, outgoing: false, status: .delivered))
        XCTAssertEqual(db.totalUnreadCount(), 2)
        db.markConversationRead(conversationId: conv)
        XCTAssertEqual(db.totalUnreadCount(), 0)
    }

    func testCurrentUserIdComesFromTheSavedSession() {
        XCTAssertNil(SessionStore.currentUserId)
        try? KeychainManager.shared.saveString(key: "jwt_refresh_token", value: "r")
        SessionStore.save(
            user: UserProfile(id: "me-123", username: "me", displayName: "Me", role: "member"),
            device: DeviceProfile(id: "d", deviceName: "iPhone", identityKeyPub: "k")
        )
        XCTAssertEqual(SessionStore.currentUserId, "me-123")
    }
}
