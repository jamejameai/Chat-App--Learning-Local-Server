import XCTest
@testable import MiniTelegram

final class ProfileAvatarTests: XCTestCase {
    func testIllustratedAvatarPresetsHaveStableStorageValues() {
        XCTAssertEqual(IllustratedAvatarPreset.allCases.count, 12)

        for preset in IllustratedAvatarPreset.allCases {
            XCTAssertEqual(
                IllustratedAvatarPreset(storageValue: preset.storageValue),
                preset
            )
        }
    }

    func testUnknownPresetIsRejectedAndLegacyEmojiMapsToIllustration() {
        XCTAssertNil(IllustratedAvatarPreset(storageValue: "illustrated-avatar:unknown"))
        XCTAssertEqual(IllustratedAvatarPreset(storageValue: "🦊"), .fox)
        XCTAssertNil(IllustratedAvatarPreset(storageValue: ""))
    }

    func testDeveloperProfileUsesServerFieldNamesAndPreservesPinnedProjects() throws {
        let project = DeveloperProject(
            id: "project-1",
            title: "Our Chat",
            summary: "A private messaging app",
            technologies: ["SwiftUI", "NestJS"],
            repositoryURL: "https://github.com/example/our-chat",
            liveURL: "https://example.com",
            isPinned: true
        )
        let profile = DeveloperProfile(
            headline: "iOS Developer",
            skills: ["Swift", "SwiftUI"],
            projects: [project],
            websiteURL: "https://example.com",
            githubURL: "https://github.com/example",
            socialLinks: DeveloperSocialLinks(linkedinURL: "https://linkedin.com/in/example"),
            currentlyBuilding: "Our Chat",
            workAvailability: "open_to_opportunities",
            location: "Phnom Penh"
        )

        let encoded = try JSONEncoder().encode(profile)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decoded = try JSONDecoder().decode(DeveloperProfile.self, from: encoded)

        XCTAssertNotNil(object["website_url"])
        XCTAssertNil(object["websiteURL"])
        XCTAssertEqual(decoded, profile)
        XCTAssertTrue(decoded.projects[0].isPinned)
    }

    func testEmptyDeveloperProfileDecodesForExistingAccounts() throws {
        let profile = try JSONDecoder().decode(DeveloperProfile.self, from: Data("{}".utf8))

        XCTAssertTrue(profile.skills.isEmpty)
        XCTAssertTrue(profile.projects.isEmpty)
        XCTAssertNil(profile.headline)
    }
}
