import SwiftUI
import Combine

/// Manages fetching system metrics, users list, updating user status/roles, revoking sessions,
/// deleting users, and broadcasting announcements.
@MainActor
public final class AdminViewModel: ObservableObject {
    @Published public var stats: SystemStatsDTO?
    @Published public var users: [AdminUserDTO] = []
    @Published public var searchQuery: String = ""
    @Published public var selectedRoleFilter: String = "all" // "all", "owner", "superadmin", "member"
    @Published public var isLoading: Bool = false
    @Published public var isPerformingAction: Bool = false
    @Published public var actionFeedbackMessage: String?
    @Published public var errorMessage: String?

    // Broadcast sheet states
    @Published public var showingBroadcastSheet: Bool = false
    @Published public var broadcastTitle: String = ""
    @Published public var broadcastMessage: String = ""
    @Published public var isBroadcasting: Bool = false

    public init() {}

    public var filteredUsers: [AdminUserDTO] {
        users.filter { user in
            let matchesRole: Bool
            if selectedRoleFilter == "all" {
                matchesRole = true
            } else {
                matchesRole = user.role.lowercased() == selectedRoleFilter.lowercased()
            }

            guard matchesRole else { return false }

            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if q.isEmpty { return true }

            return user.username.lowercased().contains(q) ||
                   user.display_name.lowercased().contains(q) ||
                   (user.phone_number?.contains(q) ?? false)
        }
    }

    public func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let fetchStats: SystemStatsDTO? = {
            try? await APIClient.shared.request(endpoint: "/admin/stats")
        }()

        async let fetchUsers: [AdminUserDTO]? = {
            try? await APIClient.shared.request(endpoint: "/admin/users?limit=100")
        }()

        let (statsRes, usersRes) = await (fetchStats, fetchUsers)
        if let statsRes {
            self.stats = statsRes
        }
        if let usersRes {
            self.users = usersRes
        }
    }

    public func updateUserStatus(userId: String, newStatus: String) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let payload = UpdateUserStatusPayload(status: newStatus)
            let updated: AdminUserDTO = try await APIClient.shared.request(
                endpoint: "/admin/users/\(userId)/status",
                method: "PATCH",
                body: payload
            )
            if let idx = users.firstIndex(where: { $0.id == userId }) {
                users[idx] = updated
            }
            showFeedback("Account status updated to \(newStatus)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func updateUserRole(userId: String, newRole: String) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let payload = UpdateUserRolePayload(role: newRole)
            let updated: AdminUserDTO = try await APIClient.shared.request(
                endpoint: "/admin/users/\(userId)/role",
                method: "PATCH",
                body: payload
            )
            if let idx = users.firstIndex(where: { $0.id == userId }) {
                users[idx] = updated
            }
            showFeedback("User role changed to \(newRole)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func revokeUserSessions(userId: String) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            struct RevokeRes: Codable { let success: Bool }
            let _: RevokeRes = try await APIClient.shared.request(
                endpoint: "/admin/users/\(userId)/sessions",
                method: "DELETE"
            )
            await loadData()
            showFeedback("User sessions revoked and disconnected")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteUser(userId: String) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            struct DelRes: Codable { let success: Bool }
            let _: DelRes = try await APIClient.shared.request(
                endpoint: "/admin/users/\(userId)",
                method: "DELETE"
            )
            users.removeAll { $0.id == userId }
            showFeedback("User deleted from system")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func sendBroadcast() async {
        let t = broadcastTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = broadcastMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !m.isEmpty else { return }

        isBroadcasting = true
        defer { isBroadcasting = false }

        do {
            struct OkRes: Codable { let success: Bool }
            let payload = BroadcastPayload(title: t, message: m)
            let _: OkRes = try await APIClient.shared.request(
                endpoint: "/admin/broadcast",
                method: "POST",
                body: payload
            )
            broadcastTitle = ""
            broadcastMessage = ""
            showingBroadcastSheet = false
            showFeedback("Broadcast sent to all active users")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func showFeedback(_ text: String) {
        actionFeedbackMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.actionFeedbackMessage == text {
                withAnimation { self.actionFeedbackMessage = nil }
            }
        }
    }
}
