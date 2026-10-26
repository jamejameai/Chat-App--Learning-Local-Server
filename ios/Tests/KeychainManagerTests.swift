import XCTest
@testable import MiniTelegram

final class KeychainManagerTests: XCTestCase {

    private let key = "keychain_manager_tests_item"

    override func tearDown() {
        KeychainManager.shared.delete(key: key)
        super.tearDown()
    }

    func testSaveAndReadBack() throws {
        // Fails with errSecMissingEntitlement (-34018) when the app is built unsigned
        try KeychainManager.shared.saveString(key: key, value: "access-token-1")
        XCTAssertEqual(try KeychainManager.shared.getString(key: key), "access-token-1")
    }

    func testSaveOverwritesExistingValue() throws {
        try KeychainManager.shared.saveString(key: key, value: "old")
        try KeychainManager.shared.saveString(key: key, value: "new")
        XCTAssertEqual(try KeychainManager.shared.getString(key: key), "new")
    }

    func testDeleteRemovesValue() throws {
        try KeychainManager.shared.saveString(key: key, value: "temp")
        KeychainManager.shared.delete(key: key)
        XCTAssertThrowsError(try KeychainManager.shared.getString(key: key))
    }
}
