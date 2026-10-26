import XCTest
@testable import MiniTelegram

final class SessionPersistenceTests: XCTestCase {

    private let user = UserProfile(id: "u-1", username: "alice", displayName: "Alice", role: "member", phoneNumber: "+855 12", avatarUrl: nil, bio: "hi")
    private let device = DeviceProfile(id: "d-1", deviceName: "iPhone", identityKeyPub: "pub")
    private let suite = "SessionPersistenceTests"

    override func setUp() {
        super.setUp()
        SessionStore.clear()
        try? KeychainManager.shared.saveString(key: "jwt_refresh_token", value: "refresh-token")
        try? KeychainManager.shared.saveString(key: "jwt_access_token", value: "access-token")
    }

    override func tearDown() {
        SessionStore.clear()
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testLoggedInUserStaysLoggedInAfterRelaunch() {
        AppState().setAuthenticated(user: user, device: device)

        let relaunched = AppState(restoreSession: true)

        XCTAssertTrue(relaunched.isAuthenticated)
        XCTAssertEqual(relaunched.currentUser, user)
        XCTAssertEqual(relaunched.currentDevice, device)
    }

    func testNoSessionMeansLoginScreen() {
        XCTAssertFalse(AppState(restoreSession: true).isAuthenticated)
    }

    func testSessionWithoutRefreshTokenIsNotResumed() {
        AppState().setAuthenticated(user: user, device: device)
        KeychainManager.shared.delete(key: "jwt_refresh_token")

        XCTAssertFalse(AppState(restoreSession: true).isAuthenticated)
    }

    func testLogoutForgetsEverything() {
        let state = AppState()
        state.setAuthenticated(user: user, device: device)
        state.logout()

        XCTAssertFalse(AppState(restoreSession: true).isAuthenticated)
        XCTAssertThrowsError(try KeychainManager.shared.getString(key: "jwt_refresh_token"))
        XCTAssertThrowsError(try KeychainManager.shared.getString(key: "jwt_access_token"))
    }

    func testProfileEditsAreRemembered() {
        let state = AppState()
        state.setAuthenticated(user: user, device: device)
        state.updateCurrentUser(displayName: "Alice Renamed", bio: "new bio")

        let relaunched = AppState(restoreSession: true)
        XCTAssertEqual(relaunched.currentUser?.displayName, "Alice Renamed")
        XCTAssertEqual(relaunched.currentUser?.bio, "new bio")
    }

    func testServerRejectingTheSessionLogsOut() {
        let state = AppState()
        state.setAuthenticated(user: user, device: device)

        NotificationCenter.default.post(name: .sessionExpired, object: nil)
        let loggedOut = expectation(description: "logged out")
        DispatchQueue.main.async {
            XCTAssertFalse(state.isAuthenticated)
            XCTAssertFalse(AppState(restoreSession: true).isAuthenticated)
            loggedOut.fulfill()
        }
        wait(for: [loggedOut], timeout: 2)
    }

    func testReinstalledAppDoesNotResumeTheOldInstallsSession() {
        let defaults = UserDefaults(suiteName: suite)!
        AppState().setAuthenticated(user: user, device: device)

        // First launch of a (re)installed app: no install marker yet -> old Keychain session is dropped
        SessionStore.discardIfReinstalled(defaults: defaults)
        XCTAssertNil(SessionStore.load())

        // Later launches of the same install keep the session
        AppState().setAuthenticated(user: user, device: device)
        try? KeychainManager.shared.saveString(key: "jwt_refresh_token", value: "refresh-token")
        SessionStore.discardIfReinstalled(defaults: defaults)
        XCTAssertNotNil(SessionStore.load())
    }
}
