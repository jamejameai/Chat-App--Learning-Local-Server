import Foundation

public final class LocalDatabaseManager: @unchecked Sendable {
    public static let shared = LocalDatabaseManager()

    private let lock = NSRecursiveLock()
    private var conversations: [String: ConversationItem] = [:]
    private var messagesByConversation: [String: [ChatMessage]] = [:]
    private let storageDirectory: URL

    public init(customStorageDirectory: URL? = nil) {
        if let custom = customStorageDirectory {
            self.storageDirectory = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageDirectory = appSupport.appendingPathComponent("MiniTelegramDatabase", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: self.storageDirectory, withIntermediateDirectories: true)
        loadFromDisk()
    }

    // MARK: - Conversations
    public func saveConversation(_ conversation: ConversationItem) {
        lock.lock()
        defer { lock.unlock() }

        conversations[conversation.id] = conversation
        persistConversations()
    }

    public func saveConversations(_ items: [ConversationItem]) {
        lock.lock()
        defer { lock.unlock() }

        for item in items {
            conversations[item.id] = item
        }
        persistConversations()
    }

    public func getConversations() -> [ConversationItem] {
        lock.lock()
        defer { lock.unlock() }

        return conversations.values.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            let t0 = $0.lastMessageTimestamp ?? Date.distantPast
            let t1 = $1.lastMessageTimestamp ?? Date.distantPast
            return t0 > t1
        }
    }

    public func getConversation(byId id: String) -> ConversationItem? {
        lock.lock()
        defer { lock.unlock() }

        return conversations[id]
    }

    // MARK: - Messages
    public func saveMessage(_ message: ChatMessage) {
        lock.lock()
        defer { lock.unlock() }

        var list = messagesByConversation[message.conversationId] ?? []

        // Idempotency: if message with this id exists, update it
        if let idx = list.firstIndex(where: { $0.id == message.id }) {
            list[idx] = message
        } else {
            list.append(message)
        }

        // Sort by sequenceId, then timestamp
        list.sort {
            if $0.sequenceId != $1.sequenceId && $0.sequenceId > 0 && $1.sequenceId > 0 {
                return $0.sequenceId < $1.sequenceId
            }
            return $0.timestamp < $1.timestamp
        }

        messagesByConversation[message.conversationId] = list

        // Update conversation summary
        if var conv = conversations[message.conversationId] {
            if !message.text.isEmpty {
                conv.lastMessageText = message.text
            } else if let vn = message.voiceNote {
                conv.lastMessageText = "🎤 Voice message (\(Int(vn.durationSeconds))s)"
            } else if let att = message.attachment {
                conv.lastMessageText = "📎 \(att.fileName)"
            } else {
                conv.lastMessageText = "Message"
            }
            conv.lastMessageTimestamp = message.timestamp
            if message.sequenceId > conv.lastSequenceId {
                conv.lastSequenceId = message.sequenceId
            }
            if !message.isOutgoing && message.status != .read {
                conv.unreadCount += 1
            }
            conversations[message.conversationId] = conv
            persistConversations()
        }

        persistMessages(conversationId: message.conversationId)
    }

    public func saveMessages(_ newMessages: [ChatMessage], for conversationId: String) {
        lock.lock()
        defer { lock.unlock() }

        for msg in newMessages {
            saveMessage(msg)
        }
    }

    public func getMessages(conversationId: String, limit: Int = 100, offset: Int = 0) -> [ChatMessage] {
        lock.lock()
        defer { lock.unlock() }

        guard let list = messagesByConversation[conversationId] else {
            return []
        }

        guard offset < list.count else {
            return []
        }

        let start = max(0, list.count - offset - limit)
        let end = list.count - offset
        return Array(list[start..<end])
    }

    public func updateMessageStatus(messageId: String, conversationId: String, status: MessageDeliveryStatus) {
        lock.lock()
        defer { lock.unlock() }

        guard var list = messagesByConversation[conversationId],
              let idx = list.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        list[idx].status = status
        messagesByConversation[conversationId] = list
        persistMessages(conversationId: conversationId)
    }

    public func markConversationRead(conversationId: String) {
        lock.lock()
        defer { lock.unlock() }

        if var conv = conversations[conversationId] {
            conv.unreadCount = 0
            conversations[conversationId] = conv
            persistConversations()
        }

        if var list = messagesByConversation[conversationId] {
            for i in 0..<list.count {
                if !list[i].isOutgoing && list[i].status != .read {
                    list[i].status = .read
                }
            }
            messagesByConversation[conversationId] = list
            persistMessages(conversationId: conversationId)
        }
    }

    // MARK: - Reactions
    public func toggleReaction(messageId: String, conversationId: String, emoji: String, userId: String) {
        lock.lock()
        defer { lock.unlock() }

        guard var list = messagesByConversation[conversationId],
              let idx = list.firstIndex(where: { $0.id == messageId }) else {
            return
        }

        var reactions = list[idx].reactions
        if let rIdx = reactions.firstIndex(where: { $0.emoji == emoji }) {
            var item = reactions[rIdx]
            if let uIdx = item.userIds.firstIndex(of: userId) {
                item.userIds.remove(at: uIdx)
                item.count -= 1
            } else {
                item.userIds.append(userId)
                item.count += 1
            }

            if item.count <= 0 {
                reactions.remove(at: rIdx)
            } else {
                reactions[rIdx] = item
            }
        } else {
            reactions.append(ReactionItem(emoji: emoji, count: 1, userIds: [userId]))
        }

        list[idx].reactions = reactions
        messagesByConversation[conversationId] = list
        persistMessages(conversationId: conversationId)
    }

    // MARK: - Search
    public func searchMessages(query: String) -> [ChatMessage] {
        lock.lock()
        defer { lock.unlock() }

        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else { return [] }

        var results: [ChatMessage] = []
        for (_, msgs) in messagesByConversation {
            for msg in msgs {
                if msg.text.lowercased().contains(cleanQuery) {
                    results.append(msg)
                }
            }
        }

        return results.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Clear / Reset
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }

        conversations.removeAll()
        messagesByConversation.removeAll()

        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - Private Persistence
    private func persistConversations() {
        let file = storageDirectory.appendingPathComponent("conversations.json")
        let list = Array(conversations.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func persistMessages(conversationId: String) {
        let safeId = conversationId.replacingOccurrences(of: "/", with: "_")
        let file = storageDirectory.appendingPathComponent("messages_\(safeId).json")
        let list = messagesByConversation[conversationId] ?? []
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func loadFromDisk() {
        // Load conversations
        let convFile = storageDirectory.appendingPathComponent("conversations.json")
        if let data = try? Data(contentsOf: convFile),
           let list = try? JSONDecoder().decode([ConversationItem].self, from: data) {
            for item in list {
                conversations[item.id] = item
            }
        }

        // Load message files
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("messages_") && file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let list = try? JSONDecoder().decode([ChatMessage].self, from: data),
                   let first = list.first {
                    messagesByConversation[first.conversationId] = list
                }
            }
        }
    }
}
