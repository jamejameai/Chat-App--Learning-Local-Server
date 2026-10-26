import XCTest
@testable import MiniTelegram

/// Serves canned responses so reachability logic can be tested without a server.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, body: String))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result = StubURLProtocol.handler?(request) ?? (status: 500, body: "")
        let response = HTTPURLResponse(url: request.url!, statusCode: result.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ServerReachabilityTests: XCTestCase {

    private let lan = "http://100.78.0.52:3001/api/v1"
    private let tunnel = "https://quiet-river-1234.trycloudflare.com/api/v1"

    private var session: URLSession!
    private var defaults: UserDefaults!
    private let suite = "ServerReachabilityTests"

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - candidates

    func testHomeAddressComesFirstThenInternetAddress() {
        XCTAssertEqual(ServerReachability.candidates(primary: lan, publicURL: tunnel), [lan, tunnel])
    }

    func testBonjourAndLocalIPCandidatesAreIncludedBeforeInternetAddress() {
        let bonjour = "http://macbook.local:3001/api/v1"
        let localIP = "http://192.168.1.39:3001/api/v1"
        XCTAssertEqual(
            ServerReachability.candidates(primary: lan, localBonjourURL: bonjour, localIPURL: localIP, publicURL: tunnel),
            [lan, bonjour, localIP, tunnel]
        )
    }

    func testBuiltInInternetAddressIsTheLastResort() {
        let seed = "https://seed-name-5678.trycloudflare.com/api/v1"
        XCTAssertEqual(
            ServerReachability.candidates(primary: lan, publicURL: tunnel, seedPublicURL: seed),
            [lan, tunnel, seed]
        )
        // A phone that never visited home has no learned address: the built-in one is used
        XCTAssertEqual(
            ServerReachability.candidates(primary: lan, publicURL: nil, seedPublicURL: seed),
            [lan, seed]
        )
        // Same address learned and built in: only tried once
        XCTAssertEqual(
            ServerReachability.candidates(primary: lan, publicURL: seed, seedPublicURL: seed),
            [lan, seed]
        )
    }

    func testCandidatesDropBlanksDuplicatesAndTrailingSlashes() {
        XCTAssertEqual(ServerReachability.candidates(primary: lan + "/", publicURL: lan), [lan])
        XCTAssertEqual(ServerReachability.candidates(primary: lan, publicURL: nil), [lan])
        XCTAssertEqual(ServerReachability.candidates(primary: lan, publicURL: "  "), [lan])
    }

    // MARK: - firstReachable

    func testUsesHomeAddressWhenItAnswers() async {
        let chosen = await ServerReachability.firstReachable(in: [lan, tunnel]) { _ in true }
        XCTAssertEqual(chosen, lan)
    }

    func testFallsBackToInternetAddressWhenAwayFromHome() async {
        let chosen = await ServerReachability.firstReachable(in: [lan, tunnel]) { $0 == self.tunnel }
        XCTAssertEqual(chosen, tunnel)
    }

    func testReturnsNilWhenNothingAnswers() async {
        let chosen = await ServerReachability.firstReachable(in: [lan, tunnel]) { _ in false }
        XCTAssertNil(chosen)
    }

    // MARK: - probeHealth

    func testHealthyServerIsReachable() async {
        StubURLProtocol.handler = { _ in (200, #"{"status":"ok","database":"connected"}"#) }
        let ok = await ServerReachability.probeHealth(lan, session: session)
        XCTAssertTrue(ok)
    }

    func testSomeOtherDeviceOnTheSameAddressIsNotTreatedAsOurServer() async {
        StubURLProtocol.handler = { _ in (200, "<html>router login</html>") }
        let ok = await ServerReachability.probeHealth(lan, session: session)
        XCTAssertFalse(ok)
    }

    func testServerErrorIsNotReachable() async {
        StubURLProtocol.handler = { _ in (503, #"{"status":"ok"}"#) }
        let ok = await ServerReachability.probeHealth(lan, session: session)
        XCTAssertFalse(ok)
    }

    // MARK: - learnPublicURL

    func testLearnsInternetAddressFromServer() async {
        let tunnel = self.tunnel
        StubURLProtocol.handler = { _ in (200, #"{"public_url":"\#(tunnel)"}"#) }
        await ServerReachability.learnPublicURL(from: lan, defaults: defaults, session: session)
        XCTAssertEqual(defaults.string(forKey: ServerReachability.publicURLKey), tunnel)
    }

    func testIgnoresInsecureOrMissingInternetAddress() async {
        StubURLProtocol.handler = { _ in (200, #"{"public_url":"http://evil.example.com/api/v1"}"#) }
        await ServerReachability.learnPublicURL(from: lan, defaults: defaults, session: session)
        XCTAssertNil(defaults.string(forKey: ServerReachability.publicURLKey))

        StubURLProtocol.handler = { _ in (200, #"{"public_url":null}"#) }
        await ServerReachability.learnPublicURL(from: lan, defaults: defaults, session: session)
        XCTAssertNil(defaults.string(forKey: ServerReachability.publicURLKey))
    }

    func testKeepsPreviouslyLearnedAddressWhenServerCannotAnswer() async {
        defaults.set(tunnel, forKey: ServerReachability.publicURLKey)
        StubURLProtocol.handler = { _ in (500, "") }
        await ServerReachability.learnPublicURL(from: lan, defaults: defaults, session: session)
        XCTAssertEqual(defaults.string(forKey: ServerReachability.publicURLKey), tunnel)
    }
}
