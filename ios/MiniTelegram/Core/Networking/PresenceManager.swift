import Foundation
import Combine
import SwiftUI

public struct UserPresenceState: Sendable, Equatable {
    public let isOnline: Bool
    public let lastSeenAt: Date?

    public init(isOnline: Bool, lastSeenAt: Date? = nil) {
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
    }
}

@MainActor
public final class PresenceManager: ObservableObject {
    public static let shared = PresenceManager()

    @Published public private(set) var presenceMap: [String: UserPresenceState] = [:]

    private var cancellables = Set<AnyCancellable>()
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let fallbackIsoFormatter = ISO8601DateFormatter()

    private init() {
        setupSubscriptions()
    }

    private func setupSubscriptions() {
        NotificationCenter.default.publisher(for: .presenceUpdated)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] userInfo in
                guard let self = self,
                      let userId = userInfo["user_id"] as? String,
                      let isOnline = userInfo["is_online"] as? Bool else { return }

                var lastSeenDate: Date?
                if let lastSeenStr = userInfo["last_seen"] as? String {
                    lastSeenDate = self.parseISO(lastSeenStr)
                }

                let existing = self.presenceMap[userId]
                self.presenceMap[userId] = UserPresenceState(
                    isOnline: isOnline,
                    lastSeenAt: isOnline ? (lastSeenDate ?? Date()) : (lastSeenDate ?? existing?.lastSeenAt ?? Date())
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .presenceSnapshotReceived)
            .compactMap { $0.userInfo?["online_user_ids"] as? [String] }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] onlineIds in
                guard let self = self else { return }
                for id in onlineIds {
                    let existing = self.presenceMap[id]
                    self.presenceMap[id] = UserPresenceState(isOnline: true, lastSeenAt: existing?.lastSeenAt ?? Date())
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .realtimeReconnected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestSync()
            }
            .store(in: &cancellables)
    }

    public func requestSync() {
        RealtimeService.shared.requestPresenceSync()
    }

    public func recordInitialPresence(userId: String, isOnline: Bool, lastSeenAt: String?) {
        let date = lastSeenAt != nil ? parseISO(lastSeenAt!) : nil
        let existing = presenceMap[userId]
        presenceMap[userId] = UserPresenceState(
            isOnline: isOnline,
            lastSeenAt: date ?? existing?.lastSeenAt
        )
    }

    public func isOnline(_ userId: String?, fallback: Bool = false) -> Bool {
        guard let userId = userId, !userId.isEmpty else { return false }
        if let state = presenceMap[userId] {
            return state.isOnline
        }
        return fallback
    }

    public func lastSeen(_ userId: String?) -> Date? {
        guard let userId = userId, !userId.isEmpty else { return nil }
        return presenceMap[userId]?.lastSeenAt
    }

    public func statusText(for userId: String?, isOnlineFallback: Bool = false) -> String {
        guard let userId = userId, !userId.isEmpty else { return "" }
        if let state = presenceMap[userId] {
            if state.isOnline {
                return "Online"
            }
            if let date = state.lastSeenAt {
                return formatLastSeen(date)
            }
        }
        if isOnlineFallback {
            return "Online"
        }
        return ""
    }

    public func formatLastSeen(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return "Last seen just now"
        }
        if interval < 3600 {
            let minutes = max(1, Int(interval / 60))
            return "Last seen \(minutes)m ago"
        }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        if calendar.isDateInToday(date) {
            return "Last seen today at \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Last seen yesterday at \(timeFormatter.string(from: date))"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        return "Last seen \(dateFormatter.string(from: date))"
    }

    private func parseISO(_ str: String) -> Date? {
        isoFormatter.date(from: str) ?? fallbackIsoFormatter.date(from: str)
    }
}
