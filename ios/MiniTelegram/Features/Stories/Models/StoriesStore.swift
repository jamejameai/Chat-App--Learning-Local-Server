import Foundation
import SwiftUI
import UIKit

/// App-wide story feed: who has stories, which ones I've seen, and posting my own.
@MainActor
public final class StoriesStore: ObservableObject {
    public static let shared = StoriesStore()

    @Published public private(set) var feed: [UserStories] = []
    @Published public private(set) var isPosting = false
    @Published public var errorMessage: String?

    private var observers: [NSObjectProtocol] = []
    private var loadTask: Task<Void, Never>?

    private init() {
        // A friend posted, or we reconnected after being offline: refresh the rings
        for name in [Notification.Name.storiesChanged, .realtimeReconnected] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in StoriesStore.shared.refresh() }
            })
        }
    }

    public var myStories: UserStories? { feed.first { $0.is_me } }
    public var friendStories: [UserStories] { feed.filter { !$0.is_me } }

    public func ringState(for userId: String?) -> StoryRingState {
        guard let userId, let entry = feed.first(where: { $0.user_id == userId }), !entry.stories.isEmpty else {
            return .none
        }
        return entry.has_unseen ? .unseen : .seen
    }

    public func stories(for userId: String?) -> UserStories? {
        guard let userId else { return nil }
        return feed.first { $0.user_id == userId && !$0.stories.isEmpty }
    }

    /// Forgets the previous account's stories on logout.
    public func reset() {
        loadTask?.cancel()
        feed = []
        errorMessage = nil
    }

    /// Reloads the feed, coalescing overlapping calls.
    public func refresh() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    public func load() async {
        do {
            let fresh: [UserStories] = try await APIClient.shared.request(endpoint: "/stories")
            if !Task.isCancelled { feed = fresh }
        } catch {
            // Keep showing the last feed; the next refresh will catch up
        }
    }

    /// Encrypts and uploads the photo, then posts it as a 24-hour story.
    @discardableResult
    public func post(image: UIImage, caption: String) async -> Bool {
        guard let jpeg = Self.storyJPEG(from: image) else {
            errorMessage = "Couldn't read that photo."
            return false
        }
        isPosting = true
        defer { isPosting = false }
        do {
            let uploaded = try await AttachmentManager.shared.uploadAttachment(
                fileData: jpeg,
                mimeType: "image/jpeg",
                fileName: "story.jpg"
            )
            struct Body: Encodable {
                let attachment_id: String
                let media_key: String
                let media_iv: String
                let media_sha256: String
                let mime_type: String
                let caption: String?
            }
            struct Created: Decodable { let id: String }
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let _: Created = try await APIClient.shared.request(
                endpoint: "/stories",
                method: "POST",
                body: Body(
                    attachment_id: uploaded.id,
                    media_key: uploaded.keyBase64,
                    media_iv: uploaded.ivBase64,
                    media_sha256: uploaded.sha256Checksum,
                    mime_type: "image/jpeg",
                    caption: trimmed.isEmpty ? nil : String(trimmed.prefix(200))
                )
            )
            await load()
            return true
        } catch {
            errorMessage = "Couldn't post your story. Check your connection and try again."
            return false
        }
    }

    /// Marks a story as seen right away on screen, then tells the server.
    public func markViewed(userId: String, storyId: String) {
        guard let entryIndex = feed.firstIndex(where: { $0.user_id == userId }),
              let storyIndex = feed[entryIndex].stories.firstIndex(where: { $0.id == storyId }),
              !feed[entryIndex].stories[storyIndex].viewed else { return }

        feed[entryIndex].stories[storyIndex].viewed = true
        feed[entryIndex].has_unseen = feed[entryIndex].stories.contains { !$0.viewed }

        struct Ok: Decodable { let success: Bool }
        Task {
            let _: Ok? = try? await APIClient.shared.request(endpoint: "/stories/\(storyId)/view", method: "POST")
        }
    }

    public func delete(storyId: String) async {
        struct Ok: Decodable { let success: Bool }
        do {
            let _: Ok = try await APIClient.shared.request(endpoint: "/stories/\(storyId)", method: "DELETE")
            await load()
        } catch {
            errorMessage = "Couldn't delete the story."
        }
    }

    public struct Viewer: Decodable, Identifiable, Sendable {
        public let user_id: String
        public let username: String
        public let display_name: String
        public let avatar_url: String?
        public let viewed_at: String
        public var id: String { user_id }
    }

    public typealias ReactionSummary = StoryReactionSummary

    public func viewers(storyId: String) async -> [Viewer] {
        (try? await APIClient.shared.request(endpoint: "/stories/\(storyId)/viewers")) ?? []
    }

    @discardableResult
    public func react(storyId: String, reaction: String) async -> Bool {
        struct Body: Encodable { let reaction: String }
        struct Ok: Decodable { let success: Bool }
        do {
            let _: Ok = try await APIClient.shared.request(
                endpoint: "/stories/\(storyId)/react",
                method: "POST",
                body: Body(reaction: reaction)
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func reply(storyId: String, text: String) async -> Bool {
        struct Body: Encodable { let text: String }
        struct Ok: Decodable { let success: Bool }
        do {
            let _: Ok = try await APIClient.shared.request(
                endpoint: "/stories/\(storyId)/reply",
                method: "POST",
                body: Body(text: text)
            )
            return true
        } catch {
            return false
        }
    }

    public func reactions(storyId: String) async -> [ReactionSummary] {
        (try? await APIClient.shared.request(endpoint: "/stories/\(storyId)/reactions")) ?? []
    }

    /// Full-screen sized JPEG (longest side 1600 px) so stories upload quickly.
    static func storyJPEG(from image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
