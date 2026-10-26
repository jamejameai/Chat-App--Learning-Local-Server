import SwiftUI
import Combine

public enum LuxuryAlertType: Equatable {
    case incomingCall(callerName: String, callId: String, convId: String, callType: String, avatarUrl: String?, borderTemplate: ProfileBorderTemplate)
    case missedCall(callerName: String, callerUserId: String, convId: String, callType: String, time: String)
    case friendAlert(name: String, username: String, avatarUrl: String?, borderTemplate: ProfileBorderTemplate, isSender: Bool)
}

public struct LuxuryAlertItem: Identifiable, Equatable {
    public let id = UUID()
    public let type: LuxuryAlertType
}

@MainActor
public final class LuxuryAlertManager: ObservableObject {
    public static let shared = LuxuryAlertManager()

    @Published public var currentAlert: LuxuryAlertItem? = nil
    private var dismissTask: Task<Void, Never>?

    private init() {
        setupListeners()
    }

    private func setupListeners() {
        // Listen for call.incoming from RealtimeService
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OurChat.realtimeIncomingCall"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, let dict = note.object as? [String: Any] else { return }
            let callerName = dict["caller_name"] as? String ?? "Incoming Call"
            let callId = dict["call_id"] as? String ?? ""
            let convId = dict["conversation_id"] as? String ?? ""
            let callType = dict["call_type"] as? String ?? "audio"
            let avatarUrl = dict["caller_avatar_url"] as? String
            let border = ProfileBorderTemplate.from(raw: dict["caller_border_template"] as? String)
            self.showIncomingCall(callerName: callerName, callId: callId, convId: convId, callType: callType, avatarUrl: avatarUrl, borderTemplate: border)
        }

        // Listen for call.missed
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OurChat.realtimeMissedCall"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, let dict = note.object as? [String: Any] else { return }
            let callerName = dict["caller_name"] as? String ?? "Unknown"
            let callerUserId = dict["caller_user_id"] as? String ?? ""
            let convId = dict["conversation_id"] as? String ?? ""
            let callType = dict["call_type"] as? String ?? "audio"
            self.showMissedCall(callerName: callerName, callerUserId: callerUserId, convId: convId, callType: callType)
        }

        // Listen for friend:alert
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OurChat.realtimeFriendAlert"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, let dict = note.object as? [String: Any] else { return }
            let name = dict["display_name"] as? String ?? dict["username"] as? String ?? "User"
            let username = dict["username"] as? String ?? ""
            let avatarUrl = dict["avatar_url"] as? String
            let border = ProfileBorderTemplate.from(raw: dict["border_template"] as? String)
            let isSender = (dict["type"] as? String) == "request_sent"
            self.showFriendAlert(name: name, username: username, avatarUrl: avatarUrl, borderTemplate: border, isSender: isSender)
        }
    }

    public func showIncomingCall(
        callerName: String,
        callId: String,
        convId: String,
        callType: String,
        avatarUrl: String? = nil,
        borderTemplate: ProfileBorderTemplate = .goldLeaf
    ) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            currentAlert = LuxuryAlertItem(
                type: .incomingCall(
                    callerName: callerName,
                    callId: callId,
                    convId: convId,
                    callType: callType,
                    avatarUrl: avatarUrl,
                    borderTemplate: borderTemplate
                )
            )
        }
    }

    public func showMissedCall(
        callerName: String,
        callerUserId: String,
        convId: String,
        callType: String
    ) {
        dismissTask?.cancel()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: Date())

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            currentAlert = LuxuryAlertItem(
                type: .missedCall(
                    callerName: callerName,
                    callerUserId: callerUserId,
                    convId: convId,
                    callType: callType,
                    time: timeStr
                )
            )
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 7 * 1_000_000_000)
            if !Task.isCancelled {
                self.dismissAlert()
            }
        }
    }

    public func showFriendAlert(
        name: String,
        username: String,
        avatarUrl: String?,
        borderTemplate: ProfileBorderTemplate = .platinumExecutive,
        isSender: Bool = false
    ) {
        dismissTask?.cancel()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            currentAlert = LuxuryAlertItem(
                type: .friendAlert(
                    name: name,
                    username: username,
                    avatarUrl: avatarUrl,
                    borderTemplate: borderTemplate,
                    isSender: isSender
                )
            )
        }

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
            if !Task.isCancelled {
                self.dismissAlert()
            }
        }
    }

    public func dismissAlert() {
        withAnimation(.easeOut(duration: 0.25)) {
            currentAlert = nil
        }
    }
}
