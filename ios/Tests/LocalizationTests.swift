import XCTest
@testable import MiniTelegram

@MainActor
final class LocalizationTests: XCTestCase {

    func testLanguageSwitching() {
        let manager = LocalizationManager.shared

        // Switch to English
        manager.setLanguage(.english)
        XCTAssertEqual(manager.currentLanguage, .english)
        let enChats = manager.localizedString(for: "tab_chats")
        XCTAssertEqual(enChats, "Chats")

        // Switch to Khmer
        manager.setLanguage(.khmer)
        XCTAssertEqual(manager.currentLanguage, .khmer)
        let kmChats = manager.localizedString(for: "tab_chats")
        XCTAssertEqual(kmChats, "ការសន្ទនា")

        // Test with args
        let enMembers = manager.localizedString(for: "groups_members_count", args: [5])
        XCTAssertTrue(enMembers.contains("5"))

        // Reset to English
        manager.setLanguage(.english)
    }

    func testMissingKeyFallback() {
        let manager = LocalizationManager.shared
        let nonexistent = manager.localizedString(for: "non_existent_key_123")
        XCTAssertEqual(nonexistent, "non_existent_key_123")
    }
}
