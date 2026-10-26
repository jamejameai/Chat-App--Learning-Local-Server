import XCTest
@testable import MiniTelegram

final class LiveLocationTests: XCTestCase {
    func testLocationDecodesServerFieldsAndMovementMetadata() throws {
        let json = """
        {
          "user_id": "friend-1",
          "share_id": "share-1",
          "username": "friend",
          "display_name": "Friend",
          "avatar_url": null,
          "latitude": 37.78,
          "longitude": -122.41,
          "heading": 92.5,
          "accuracy": 8.0,
          "updated_at": "2026-10-22T00:00:00.000Z"
        }
        """.data(using: .utf8)!

        let location = try JSONDecoder().decode(LiveLocationDTO.self, from: json)

        XCTAssertEqual(location.id, "friend-1")
        XCTAssertEqual(location.share_id, "share-1")
        XCTAssertEqual(location.display_name, "Friend")
        XCTAssertEqual(location.latitude, 37.78, accuracy: 0.0001)
        XCTAssertEqual(location.longitude, -122.41, accuracy: 0.0001)
        XCTAssertEqual(location.heading, 92.5)
    }

    func testLocationAllowsMissingMovementMetadata() throws {
        let json = """
        {
          "user_id": "friend-1",
          "username": "friend",
          "display_name": "Friend",
          "latitude": 37.78,
          "longitude": -122.41,
          "updated_at": "2026-10-22T00:00:00.000Z"
        }
        """.data(using: .utf8)!

        let location = try JSONDecoder().decode(LiveLocationDTO.self, from: json)

        XCTAssertNil(location.heading)
        XCTAssertNil(location.accuracy)
        XCTAssertNil(location.avatar_url)
    }

    func testLocationFreshnessDistinguishesLiveFromLastKnownCoordinates() {
        let encoder = ISO8601DateFormatter()
        encoder.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let recentTimestamp = encoder.string(from: Date().addingTimeInterval(-30))
        let oldTimestamp = encoder.string(from: Date().addingTimeInterval(-180))

        let recent = LiveLocationDTO(
            user_id: "friend-1",
            share_id: nil,
            username: "friend",
            display_name: "Friend",
            avatar_url: nil,
            latitude: 37.78,
            longitude: -122.41,
            heading: nil,
            accuracy: nil,
            updated_at: recentTimestamp
        )
        let old = LiveLocationDTO(
            user_id: "friend-1",
            share_id: nil,
            username: "friend",
            display_name: "Friend",
            avatar_url: nil,
            latitude: 37.78,
            longitude: -122.41,
            heading: nil,
            accuracy: nil,
            updated_at: oldTimestamp
        )

        XCTAssertTrue(recent.isFresh)
        XCTAssertFalse(old.isFresh)
    }

    func testShareStateDecodesActiveSharingForAppRelaunch() throws {
        let json = """
        {
          "sharing": true,
          "location": {
            "user_id": "me",
            "share_id": "share-1",
            "latitude": 37.78,
            "longitude": -122.41,
            "updated_at": "2026-10-22T00:00:00.000Z",
            "viewer_ids": ["friend-1"]
          }
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(LiveLocationShareState.self, from: json)

        XCTAssertTrue(state.sharing)
        XCTAssertEqual(state.location?.user_id, "me")
        XCTAssertEqual(state.location?.share_id, "share-1")
        XCTAssertEqual(state.location?.viewer_ids, ["friend-1"])
    }

    func testStopEventIdentifiesTheShareSession() throws {
        let json = """
        { "user_id": "friend-1", "share_id": "share-1" }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(LiveLocationStopEvent.self, from: json)

        XCTAssertEqual(event.user_id, "friend-1")
        XCTAssertEqual(event.share_id, "share-1")
    }

    func testShareStartPayloadIncludesExplicitAudience() throws {
        let payload = LiveLocationStartPayload(
            latitude: 37.78,
            longitude: -122.41,
            heading: 92.5,
            accuracy: 8,
            viewer_ids: ["friend-1"],
            stop_token: String(repeating: "a", count: 64)
        )

        let encoded = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertEqual(object["viewer_ids"] as? [String], ["friend-1"])
        XCTAssertEqual(object["stop_token"] as? String, String(repeating: "a", count: 64))
        XCTAssertEqual(object["latitude"] as? Double, 37.78)
    }
}
