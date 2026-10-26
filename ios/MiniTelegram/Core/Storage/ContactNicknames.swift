import Foundation

extension Notification.Name {
    /// Posted when a nickname is added, changed or removed.
    public static let contactNicknamesChanged = Notification.Name("OurChat.contactNicknamesChanged")
}

/// Nicknames you give your contacts, like renaming a contact on the iPhone. Private to this phone and
/// this account (the other person never sees them). Shown instead of their display name everywhere.
public enum ContactNicknames {
    private static var storageKey: String {
        "contact_nicknames.\(SessionStore.currentUserId ?? "anonymous")"
    }

    private static func all() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    public static func nickname(for userId: String?) -> String? {
        guard let userId else { return nil }
        return all()[userId]
    }

    /// Sets a nickname; nil or blank removes it.
    public static func set(_ nickname: String?, for userId: String) {
        var map = all()
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            map.removeValue(forKey: userId)
        } else {
            map[userId] = String(trimmed.prefix(40))
        }
        UserDefaults.standard.set(map, forKey: storageKey)
        NotificationCenter.default.post(name: .contactNicknamesChanged, object: userId)
    }

    /// The nickname if you set one, otherwise their own name.
    public static func displayName(userId: String?, fallback: String) -> String {
        nickname(for: userId) ?? fallback
    }
}
