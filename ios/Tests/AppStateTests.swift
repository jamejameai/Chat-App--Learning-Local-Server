import XCTest
@testable import MiniTelegram

final class AppStateTests: XCTestCase {

    func testInitialState() {
        let state = AppState()
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertFalse(state.isBiometricLocked)
        XCTAssertEqual(state.selectedTab, .chats)
        XCTAssertNil(state.currentUser)
        XCTAssertNil(state.currentDevice)
    }

    func testAuthenticationAndLogoutLifecycle() {
        let state = AppState()
        let user = UserProfile(id: "u-123", username: "dara", displayName: "Dara", role: "member")
        let device = DeviceProfile(id: "d-456", deviceName: "iPhone 16", identityKeyPub: "pubkey")

        state.setAuthenticated(user: user, device: device)
        XCTAssertTrue(state.isAuthenticated)
        XCTAssertEqual(state.currentUser?.username, "dara")
        XCTAssertEqual(state.currentDevice?.deviceName, "iPhone 16")

        state.logout()
        XCTAssertFalse(state.isAuthenticated)
        XCTAssertNil(state.currentUser)
        XCTAssertNil(state.currentDevice)
        XCTAssertEqual(state.selectedTab, .chats)
    }
}
