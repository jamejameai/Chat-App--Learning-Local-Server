import Foundation
import Combine
import UIKit

extension Notification.Name {
    /// Posted on the main queue after an incoming message has been saved locally; `object` is the `ChatMessage`.
    public static let chatMessageReceived = Notification.Name("OurChat.chatMessageReceived")
    /// Posted on the main queue each time the live connection (re)connects, so screens can catch up on
    /// anything that arrived while it was down.
    public static let realtimeReconnected = Notification.Name("OurChat.realtimeReconnected")
    /// Posted on the main queue when message statuses in a chat changed ("Seen"); `object` is the conversation id.
    public static let messageStatusChanged = Notification.Name("OurChat.messageStatusChanged")
    /// Posted on the main queue when a friend posts a story, so the story rings refresh.
    public static let storiesChanged = Notification.Name("OurChat.storiesChanged")
    /// Posted on the main queue when I'm added to a new chat (e.g. someone made a group with me).
    public static let conversationsChanged = Notification.Name("OurChat.conversationsChanged")
    public static let liveLocationsChanged = Notification.Name("OurChat.liveLocationsChanged")
    public static let friendsChanged = Notification.Name("OurChat.friendsChanged")
    public static let presenceUpdated = Notification.Name("OurChat.presenceUpdated")
    public static let presenceSnapshotReceived = Notification.Name("OurChat.presenceSnapshotReceived")
}

/// Live connection to the server (Socket.IO over a WebSocket).
///
/// Call `start()` once logged in and `ensureConnected()` whenever the app becomes active; the service
/// keeps itself connected (with a fresh access token on every attempt) until `stop()` is called.
/// All state is touched on the main queue.
public final class RealtimeService: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {
    public static let shared = RealtimeService()

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected = false   // Socket.IO namespace acknowledged ("40")
    private var isConnecting = false
    private var shouldStayConnected = false
    private var reconnectAttempts = 0
    private var reconnectWorkItem: DispatchWorkItem?
    /// Bumped by start()/stop(); connection attempts from an older generation are discarded.
    private var connectionGeneration = 0
    /// Conversations to (re)join after every reconnect, for typing and call events.
    private var joinedConversations = Set<String>()

    // ISO8601DateFormatter is thread-safe; only used on the main queue anyway
    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Event Callbacks
    public var onReceiptReceived: (@Sendable (String, String, MessageDeliveryStatus) -> Void)?
    public var onTypingUpdate: (@Sendable (String, String, Bool) -> Void)?
    public var onPresenceUpdate: (@Sendable (String, Bool) -> Void)?
    public var onRekeyRequired: (@Sendable (String, String) -> Void)?
    public var onMemberUpdated: (@Sendable (String, String, String) -> Void)?
    public var onIncomingCall: (@Sendable (String, String, String, String, String?, String) -> Void)?
    public var onCallEnded: (@Sendable (String) -> Void)?
    public var onLocationUpdated: (@Sendable (LiveLocationDTO) -> Void)?
    public var onLocationStopped: (@Sendable (LiveLocationStopEvent) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Starts keeping the live connection open for whoever is logged in now (after login / on launch).
    /// Always reconnects, so a new login never keeps using the previous login's connection.
    public func start() {
        DispatchQueue.main.async {
            self.shouldStayConnected = true
            self.connectionGeneration += 1
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.reconnectAttempts = 0
            self.isConnecting = false
            self.tearDown()
            self.ensureConnectedOnMain()
        }
    }

    /// Reconnects immediately if the connection is down (e.g. when the app returns to the foreground).
    public func ensureConnected() {
        DispatchQueue.main.async { self.ensureConnectedOnMain() }
    }

    /// Closes the connection and stops reconnecting (logout).
    public func stop() {
        DispatchQueue.main.async {
            self.shouldStayConnected = false
            self.connectionGeneration += 1
            self.isConnecting = false
            self.reconnectWorkItem?.cancel()
            self.reconnectWorkItem = nil
            self.joinedConversations.removeAll()
            self.tearDown()
        }
    }

    private func ensureConnectedOnMain() {
        guard shouldStayConnected, !isConnected, !isConnecting else { return }
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        isConnecting = true
        let generation = connectionGeneration

        Task {
            // Also picks the reachable server address (home network or internet) for activeBaseURL
            let token = await APIClient.shared.freshAccessToken()
            DispatchQueue.main.async { self.openSocket(token: token, generation: generation) }
        }
    }

    private func openSocket(token: String?, generation: Int) {
        // A newer start()/stop() happened while this token was being fetched: drop this attempt
        guard generation == connectionGeneration else { return }
        isConnecting = false
        guard shouldStayConnected else { return }
        guard let token else {
            scheduleReconnect()
            return
        }

        tearDown()

        let base = APIClient.shared.activeBaseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "/api/v1", with: "")
        guard let url = URL(string: "\(base)/socket.io/?EIO=4&transport=websocket&app_state=\(Self.appState)&token=\(token)") else {
            scheduleReconnect()
            return
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.webSocketTask = task
        task.resume()
        listen(on: task)
    }

    private func tearDown() {
        isConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func handleDisconnection(of task: URLSessionWebSocketTask) {
        guard task === webSocketTask else { return } // stale callback from an older socket
        tearDown()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard shouldStayConnected, reconnectWorkItem == nil else { return }
        reconnectAttempts += 1
        let delay = min(Double(1 << min(reconnectAttempts, 5)), 30.0) // 2, 4, 8, 16, 30, 30... seconds
        let work = DispatchWorkItem { [weak self] in
            self?.reconnectWorkItem = nil
            self?.ensureConnectedOnMain()
        }
        reconnectWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Public events

    public func joinConversation(conversationId: String) {
        DispatchQueue.main.async {
            self.joinedConversations.insert(conversationId)
            if self.isConnected {
                self.sendSocketIOEvent(event: "conversation.join", data: ["conversation_id": conversationId])
            }
        }
    }

    public func leaveConversation(conversationId: String) {
        DispatchQueue.main.async { self.joinedConversations.remove(conversationId) }
    }

    /// Tells the server whether the app is on screen. While it is, the server doesn't relay alerts
    /// to Bark (the app shows its own banners); in the background or closed, it does.
    public func reportAppState() {
        DispatchQueue.main.async {
            guard self.isConnected else { return } // sent again on every (re)connect
            self.sendSocketIOEvent(event: "app.state", data: ["state": Self.appState])
        }
    }

    /// "background" only once the app has really left the screen (not for e.g. Control Center).
    /// Must be called on the main queue.
    private static var appState: String {
        MainActor.assumeIsolated {
            UIApplication.shared.applicationState == .background ? "background" : "active"
        }
    }

    public func sendTyping(conversationId: String, isTyping: Bool) {
        DispatchQueue.main.async {
            guard self.isConnected else { return }
            self.sendSocketIOEvent(event: "typing.update", data: [
                "conversation_id": conversationId,
                "is_typing": isTyping
            ])
        }
    }

    public func requestPresenceSync() {
        DispatchQueue.main.async {
            guard self.isConnected else { return }
            self.sendSocketIOEvent(event: "presence.sync", data: [:])
        }
    }

    // MARK: - Socket.IO protocol

    private func listen(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self, task === self.webSocketTask else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleSocketIOMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleSocketIOMessage(text)
                    }
                @unknown default:
                    break
                }
                self.listen(on: task)

            case .failure(let error):
                print("[RealtimeService] WebSocket receive error: \(error.localizedDescription)")
                self.handleDisconnection(of: task)
            }
        }
    }

    private func handleSocketIOMessage(_ text: String) {
        // Engine.IO v4 / Socket.IO v5 frames:
        //   "0{...}"      engine open        -> reply "40" (connect to the default namespace)
        //   "40{...}"     namespace connected
        //   "41"          server disconnected us (e.g. rejected token)
        //   "2"           server ping        -> reply "3" (pong). Clients must NOT send "2" in v4:
        //                                       the server treats it as a protocol error and drops us.
        //   "42[...]"     event
        if text.hasPrefix("40") {
            isConnected = true
            reconnectAttempts = 0
            // The app may have changed state while connecting
            sendSocketIOEvent(event: "app.state", data: ["state": Self.appState])
            for conversationId in joinedConversations {
                sendSocketIOEvent(event: "conversation.join", data: ["conversation_id": conversationId])
            }
            sendSocketIOEvent(event: "presence.sync", data: [:])
            NotificationCenter.default.post(name: .realtimeReconnected, object: nil)
        } else if text.hasPrefix("41") || text.hasPrefix("44") {
            if let task = webSocketTask { handleDisconnection(of: task) }
        } else if text.hasPrefix("42") {
            let jsonString = String(text.dropFirst(2))
            guard let data = jsonString.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  array.count >= 2,
                  let eventName = array[0] as? String else {
                return
            }
            dispatchSocketIOEvent(name: eventName, payload: array[1] as? [String: Any] ?? [:])
        } else if text == "2" {
            sendRaw("3")
        } else if text.hasPrefix("0") {
            sendRaw("40")
        }
    }

    /// Sequence ids arrive as strings (Postgres BIGINT) or numbers.
    private static func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let text = value as? String { return Int64(text) ?? 0 }
        return 0
    }

    private func dispatchSocketIOEvent(name: String, payload: [String: Any]) {
        switch name {
        case "message.new":
            guard let id = payload["id"] as? String,
                  let convId = payload["conversation_id"] as? String,
                  let senderId = payload["sender_user_id"] as? String,
                  let ciphertext = payload["encrypted_payload"] as? String else {
                return
            }

            let decrypted = MessageCryptoCoordinator.shared.decryptMessage(
                conversationId: convId,
                encryptedPayloadBase64: ciphertext,
                ivBase64: payload["iv"] as? String ?? "",
                envelopeType: payload["envelope_type"] as? String ?? "e2ee_text"
            )
            let senderName = (payload["sender_display_name"] as? String)
                ?? (payload["sender_username"] as? String)
                ?? "Friend"
            let timestamp = (payload["created_at"] as? String).flatMap { Self.isoFormatter.date(from: $0) } ?? Date()

            let message = ChatMessage(
                id: id,
                conversationId: convId,
                senderUserId: senderId,
                senderDeviceId: payload["sender_device_id"] as? String ?? "",
                senderName: senderName,
                sequenceId: Self.int64(payload["sequence_id"]),
                text: decrypted.text,
                replyToMessageId: payload["reply_to_message_id"] as? String ?? decrypted.replyToMessageId,
                status: .delivered,
                timestamp: timestamp,
                isOutgoing: false,
                attachment: decrypted.attachment,
                voiceNote: decrypted.voiceNote
            )

            // Saved once here; screens and the alert manager react to the notification
            LocalDatabaseManager.shared.saveMessage(message)
            NotificationCenter.default.post(name: .chatMessageReceived, object: message)

        case "message.receipt":
            if let msgId = payload["message_id"] as? String,
               let convId = payload["conversation_id"] as? String,
               let statusStr = payload["status"] as? String {
                let status: MessageDeliveryStatus = statusStr == "read" ? .read : .delivered
                onReceiptReceived?(msgId, convId, status)

                if status == .read {
                    let readerId = payload["user_id"] as? String
                    if readerId != nil && readerId == SessionStore.currentUserId {
                        // I read this chat on another device: its notifications here are no longer needed
                        MainActor.assumeIsolated {
                            MessageAlertManager.shared.clearNotifications(conversationId: convId)
                        }
                    } else if LocalDatabaseManager.shared.markOutgoingRead(
                        conversationId: convId,
                        upToSequence: Self.int64(payload["sequence_id"])
                    ) {
                        // Someone else saw my messages: update "Seen" even if that chat isn't open
                        NotificationCenter.default.post(name: .messageStatusChanged, object: convId)
                    }
                }
            }

        case "typing.update":
            if let convId = payload["conversation_id"] as? String,
               let userId = payload["user_id"] as? String,
               let isTyping = payload["is_typing"] as? Bool {
                onTypingUpdate?(convId, userId, isTyping)
            }

        case "presence.update":
            if let userId = payload["user_id"] as? String,
               let isOnline = payload["is_online"] as? Bool {
                let lastSeen = payload["last_seen"] as? String
                onPresenceUpdate?(userId, isOnline)
                NotificationCenter.default.post(
                    name: .presenceUpdated,
                    object: nil,
                    userInfo: [
                        "user_id": userId,
                        "is_online": isOnline,
                        "last_seen": lastSeen as Any
                    ]
                )
            }

        case "presence.snapshot":
            if let onlineIds = payload["online_user_ids"] as? [String] {
                NotificationCenter.default.post(
                    name: .presenceSnapshotReceived,
                    object: nil,
                    userInfo: ["online_user_ids": onlineIds]
                )
            }

        case "conversation.rekey_required":
            if let convId = payload["conversation_id"] as? String,
               let evictedId = payload["evicted_user_id"] as? String {
                onRekeyRequired?(convId, evictedId)
            }

        case "conversation.member_updated":
            if let convId = payload["conversation_id"] as? String,
               let userId = payload["user_id"] as? String,
               let role = payload["role"] as? String {
                onMemberUpdated?(convId, userId, role)
            }

        case "call.incoming":
            if let callId = payload["call_id"] as? String,
               let convId = payload["conversation_id"] as? String,
               let callerId = payload["caller_user_id"] as? String,
               let callerName = payload["caller_name"] as? String,
               let callType = payload["call_type"] as? String {
                let convTitle = payload["conversation_title"] as? String
                onIncomingCall?(callId, convId, callerId, callerName, convTitle, callType)
                NotificationCenter.default.post(
                    name: Notification.Name("OurChat.realtimeIncomingCall"),
                    object: payload
                )
            }

        case "call.missed":
            NotificationCenter.default.post(
                name: Notification.Name("OurChat.realtimeMissedCall"),
                object: payload
            )

        case "friend:alert":
            NotificationCenter.default.post(
                name: Notification.Name("OurChat.realtimeFriendAlert"),
                object: payload
            )
            NotificationCenter.default.post(name: .friendsChanged, object: nil)

        case "story:reaction":
            NotificationCenter.default.post(
                name: Notification.Name("OurChat.realtimeStoryReaction"),
                object: payload
            )

        case "session:revoked":
            NotificationCenter.default.post(name: .sessionExpired, object: nil)

        case "conversation.created":
            NotificationCenter.default.post(name: .conversationsChanged, object: nil)

        case "story.new":
            NotificationCenter.default.post(name: .storiesChanged, object: nil)

        case "location.update":
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let location = try? JSONDecoder().decode(LiveLocationDTO.self, from: data) else {
                return
            }
            onLocationUpdated?(location)
            NotificationCenter.default.post(name: .liveLocationsChanged, object: location)

        case "location.stopped":
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let event = try? JSONDecoder().decode(LiveLocationStopEvent.self, from: data) else {
                return
            }
            onLocationStopped?(event)
            NotificationCenter.default.post(name: .liveLocationsChanged, object: event.user_id)

        case "call.ended":
            if let callId = payload["call_id"] as? String {
                onCallEnded?(callId)
            }

        default:
            break
        }
    }


    private func sendSocketIOEvent(event: String, data: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: [event, data]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        sendRaw("42\(jsonString)")
    }

    private func sendRaw(_ text: String) {
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("[RealtimeService] Error sending frame: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[RealtimeService] WebSocket connection opened")
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[RealtimeService] WebSocket closed with code \(closeCode.rawValue)")
        handleDisconnection(of: webSocketTask)
    }
}
