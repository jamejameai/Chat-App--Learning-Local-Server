import Foundation
import Combine

public final class RealtimeService: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {
    public static let shared = RealtimeService()

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var isConnected: Bool = false
    private var currentToken: String?
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts = 10
    private var pingTimer: Timer?

    // Event Callbacks
    public var onMessageReceived: (@Sendable (ChatMessage) -> Void)?
    public var onReceiptReceived: (@Sendable (String, String, MessageDeliveryStatus) -> Void)?
    public var onTypingUpdate: (@Sendable (String, String, Bool) -> Void)?
    public var onPresenceUpdate: (@Sendable (String, Bool) -> Void)?

    private override init() {
        super.init()
    }

    public func connect(token: String) {
        self.currentToken = token
        self.reconnectAttempts = 0

        disconnect()

        let base = APIClient.shared.currentBaseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "/api/v1", with: "")

        let urlString = "\(base)/socket.io/?EIO=4&transport=websocket&token=\(token)"
        guard let url = URL(string: urlString) else { return }

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        listenForMessages()
        startPingTimer()
    }

    public func disconnect() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    public func joinConversation(conversationId: String) {
        sendSocketIOEvent(event: "conversation.join", data: ["conversation_id": conversationId])
    }

    public func sendTyping(conversationId: String, isTyping: Bool) {
        sendSocketIOEvent(event: "typing.update", data: [
            "conversation_id": conversationId,
            "is_typing": isTyping
        ])
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

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
                // Continue listening
                self.listenForMessages()

            case .failure(let error):
                print("[RealtimeService] WebSocket receive error: \(error)")
                self.handleDisconnection()
            }
        }
    }

    private func handleSocketIOMessage(_ text: String) {
        // Socket.IO protocol parser
        // "0{"sid":...}" = open handshake
        // "2" = ping, respond "3" (pong)
        // "42["event", data]" = event message

        if text.starts(with: "0") {
            // Handshake open
            isConnected = true
            reconnectAttempts = 0
            // Send Socket.IO connect frame "40"
            sendRaw("40")
        } else if text == "2" {
            // Ping from server, reply pong
            sendRaw("3")
        } else if text.starts(with: "42") {
            // Event payload
            let jsonString = String(text.dropFirst(2))
            guard let data = jsonString.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  array.count >= 2,
                  let eventName = array[0] as? String else {
                return
            }

            let payload = array[1] as? [String: Any] ?? [:]
            dispatchSocketIOEvent(name: eventName, payload: payload)
        }
    }

    private func dispatchSocketIOEvent(name: String, payload: [String: Any]) {
        switch name {
        case "message.new":
            if let id = payload["id"] as? String,
               let convId = payload["conversation_id"] as? String,
               let senderId = payload["sender_user_id"] as? String,
               let ciphertext = payload["encrypted_payload"] as? String {
                
                let seq = (payload["sequence_id"] as? NSNumber)?.int64Value ?? 0
                let senderName = (payload["sender_username"] as? String) ?? "User"
                let replyTo = payload["reply_to_message_id"] as? String

                // Decrypt envelope or extract inner payload
                let decryptedText = ciphertext // In Phase 4, encrypted_payload is decrypted via DoubleRatchet
                let msg = ChatMessage(
                    id: id,
                    conversationId: convId,
                    senderUserId: senderId,
                    senderName: senderName,
                    sequenceId: seq,
                    text: decryptedText,
                    replyToMessageId: replyTo,
                    status: .delivered,
                    timestamp: Date(),
                    isOutgoing: false
                )
                onMessageReceived?(msg)
            }

        case "message.receipt":
            if let msgId = payload["message_id"] as? String,
               let convId = payload["conversation_id"] as? String,
               let statusStr = payload["status"] as? String {
                let status: MessageDeliveryStatus = statusStr == "read" ? .read : .delivered
                onReceiptReceived?(msgId, convId, status)
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
                onPresenceUpdate?(userId, isOnline)
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
        let frame = "42\(jsonString)"
        sendRaw(frame)
    }

    private func sendRaw(_ text: String) {
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("[RealtimeService] Error sending frame: \(error)")
            }
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            self?.sendRaw("2") // Socket.IO client ping
        }
    }

    private func handleDisconnection() {
        isConnected = false
        guard let token = currentToken, reconnectAttempts < maxReconnectAttempts else { return }

        reconnectAttempts += 1
        let delay = min(Double(1 << reconnectAttempts), 30.0) // Exponential backoff up to 30s
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect(token: token)
        }
    }

    // MARK: - URLSessionWebSocketDelegate
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("[RealtimeService] WebSocket connection opened")
    }

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("[RealtimeService] WebSocket closed with code \(closeCode.rawValue)")
        handleDisconnection()
    }
}
