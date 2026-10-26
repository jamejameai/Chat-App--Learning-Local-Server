import Foundation

public enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String)
    case unauthorized
    case sessionChanged
    case decodingError(Error)
    case unknown

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .networkError(let err):
            return err.localizedDescription
        case .serverError(_, let msg):
            return msg
        case .unauthorized:
            return "Session has expired or credentials are invalid"
        case .sessionChanged:
            return "The signed-in account changed before this request could be sent"
        case .decodingError(let err):
            return "Failed to parse response: \(err.localizedDescription)"
        case .unknown:
            return "An unexpected network error occurred"
        }
    }
}

// MARK: - Auto-Generated Network Configuration
// BEGIN_GENERATED_NETWORK_CONFIG
public struct GeneratedNetworkConfig {
    public static let buildId = "20261026220914"
    public static let localBonjourURL = ""
    public static let localIPURL = "http://100.78.0.52:3001/api/v1"
    public static let cloudflareURL = "https://jjserver.tail87c566.ts.net/api/v1"

    // Public Tailscale Funnel address first (any network), the Tailscale IP as fallback
    public static let defaultURL = "https://jjserver.tail87c566.ts.net/api/v1"
}
// END_GENERATED_NETWORK_CONFIG

public actor APIClient {
    public static let shared = APIClient()

    private var baseURLString: String

    /// Address currently in use (home network or internet), re-checked every `activeBaseTTL` seconds.
    private var activeBase: String?
    private var activeBaseResolvedAt: Date = .distantPast
    private var learnedPublicURL = false
    private static let activeBaseTTL: TimeInterval = 30

    private static func resolvedBaseURL() -> String {
        let currentBuildId = GeneratedNetworkConfig.buildId
        let savedBuildId = UserDefaults.standard.string(forKey: "network_config_build_id")

        // Auto-adopt the new Wi-Fi network address whenever a new build is deployed
        if savedBuildId != currentBuildId {
            UserDefaults.standard.set(currentBuildId, forKey: "network_config_build_id")
            let newDefault = GeneratedNetworkConfig.defaultURL
            UserDefaults.standard.set(newDefault, forKey: "server_base_url")
            UserDefaults.standard.removeObject(forKey: "user_selected_server_url")
            UserDefaults.standard.removeObject(forKey: ServerReachability.activeURLKey)
            UserDefaults.standard.removeObject(forKey: ServerReachability.publicURLKey)
            return newDefault
        }

        if UserDefaults.standard.bool(forKey: "user_selected_server_url"),
           let saved = UserDefaults.standard.string(forKey: "server_base_url"),
           !saved.isEmpty, !saved.contains("localhost:3000") {
            return saved
        }

        let defaultURL = GeneratedNetworkConfig.defaultURL
        UserDefaults.standard.set(defaultURL, forKey: "server_base_url")
        return defaultURL
    }

    public init() {
        self.baseURLString = Self.resolvedBaseURL()
    }

    public nonisolated var currentBaseURL: String {
        let currentBuildId = GeneratedNetworkConfig.buildId
        let savedBuildId = UserDefaults.standard.string(forKey: "network_config_build_id")

        if savedBuildId == currentBuildId,
           UserDefaults.standard.bool(forKey: "user_selected_server_url"),
           let saved = UserDefaults.standard.string(forKey: "server_base_url"),
           !saved.isEmpty, !saved.contains("localhost:3000") {
            return saved
        }

        return GeneratedNetworkConfig.defaultURL
    }

    /// The address requests are actually going to right now (home network or internet).
    /// Falls back to the configured address until the first request has picked one.
    public nonisolated var activeBaseURL: String {
        UserDefaults.standard.string(forKey: ServerReachability.activeURLKey) ?? currentBaseURL
    }

    public func setBaseURL(_ url: String) {
        self.baseURLString = url
        UserDefaults.standard.set(true, forKey: "user_selected_server_url")
        UserDefaults.standard.set(url, forKey: "server_base_url")
        // A different server has a different internet address: forget what we learned
        UserDefaults.standard.removeObject(forKey: ServerReachability.publicURLKey)
        UserDefaults.standard.removeObject(forKey: ServerReachability.activeURLKey)
        activeBase = nil
        learnedPublicURL = false
    }

    /// Picks the reachable server address: home network first, then the learned internet address.
    private func resolveBase(forceRefresh: Bool = false) async -> String {
        if !forceRefresh, let active = activeBase,
           Date().timeIntervalSince(activeBaseResolvedAt) < Self.activeBaseTTL {
            return active
        }

        let primary = baseURLString.isEmpty ? Self.resolvedBaseURL() : baseURLString
        let candidates = ServerReachability.candidates(
            primary: primary,
            localBonjourURL: GeneratedNetworkConfig.localBonjourURL,
            localIPURL: GeneratedNetworkConfig.localIPURL,
            publicURL: UserDefaults.standard.string(forKey: ServerReachability.publicURLKey),
            // Built-in starting address only while the server hasn't been changed by hand
            seedPublicURL: UserDefaults.standard.bool(forKey: "user_selected_server_url")
                ? nil : GeneratedNetworkConfig.cloudflareURL
        )
        let chosen = await ServerReachability.firstReachable(in: candidates) {
            await ServerReachability.probeHealth($0)
        } ?? primary

        activeBase = chosen
        activeBaseResolvedAt = Date()
        UserDefaults.standard.set(chosen, forKey: ServerReachability.activeURLKey)

        // Remember the server's internet address (once per launch) for when we leave home
        if !learnedPublicURL {
            learnedPublicURL = true
            Task.detached { await ServerReachability.learnPublicURL(from: chosen) }
        }
        return chosen
    }

    public func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true,
        expectedSessionUserId: String? = nil
    ) async throws -> T {
        try await performRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            requiresAuth: requiresAuth,
            allowFailover: true,
            expectedSessionUserId: expectedSessionUserId
        )
    }

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: String,
        body: (any Encodable)?,
        requiresAuth: Bool,
        allowFailover: Bool,
        expectedSessionUserId: String?,
        hasRefreshed: Bool = false
    ) async throws -> T {
        let requestUserId = requiresAuth
            ? (expectedSessionUserId ?? SessionStore.currentUserId)
            : nil
        if requiresAuth, requestUserId == nil {
            throw APIError.unauthorized
        }
        if let expectedSessionUserId,
           SessionStore.currentUserId != expectedSessionUserId {
            throw APIError.sessionChanged
        }
        let accessToken = requiresAuth
            ? try? KeychainManager.shared.getString(key: "jwt_access_token")
            : nil
        let base = await resolveBase()
        if let requestUserId, SessionStore.currentUserId != requestUserId {
            throw APIError.sessionChanged
        }
        if requiresAuth, accessToken == nil {
            throw APIError.unauthorized
        }
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accessToken {
            request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw APIError.networkError(error)
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // The address may have stopped working (e.g. left home Wi-Fi): re-check and retry once
            activeBase = nil
            if allowFailover {
                let next = await resolveBase(forceRefresh: true)
                if next != base {
                    return try await performRequest(
                        endpoint: endpoint,
                        method: method,
                        body: body,
                        requiresAuth: requiresAuth,
                        allowFailover: false,
                        expectedSessionUserId: requestUserId
                    )
                }
            }
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        if httpResponse.statusCode == 401 && requiresAuth {
            if let requestUserId, SessionStore.currentUserId != requestUserId {
                throw APIError.sessionChanged
            }
            guard !hasRefreshed else {
                // Refused even with a brand-new token: the session or device was revoked
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw APIError.unauthorized
            }

            switch await refreshAccessToken(expectedSessionUserId: requestUserId) {
            case .refreshed:
                // Retry once with the new token
                return try await self.performRequest(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    requiresAuth: requiresAuth,
                    allowFailover: allowFailover,
                    expectedSessionUserId: requestUserId,
                    hasRefreshed: true
                )
            case .rejected:
                // Only a definite "no" from the server ends the session (never being offline)
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw APIError.unauthorized
            case .unreachable:
                throw APIError.networkError(URLError(.cannotConnectToHost))
            case .sessionChanged:
                throw APIError.sessionChanged
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Parse NestJS error body
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorJson["message"] {
                let msgStr = (message as? [String])?.joined(separator: ", ") ?? "\(message)"
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: msgStr)
            }
            throw APIError.serverError(
                statusCode: httpResponse.statusCode,
                message: "HTTP Error \(httpResponse.statusCode)"
            )
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// An access token the server currently accepts. Access tokens expire after 15 minutes, so this
    /// makes one cheap authenticated call first, which refreshes the token if it has expired.
    public func freshAccessToken() async -> String? {
        struct Me: Decodable { let id: String }
        let _: Me? = try? await request(endpoint: "/auth/me")
        return try? KeychainManager.shared.getString(key: "jwt_access_token")
    }

    /// Raw bytes (attachment downloads). Renews an expired access token like `request` does, so
    /// photos and voice notes still load after the app has been open for more than 15 minutes.
    public func requestRaw(
        endpoint: String,
        method: String = "GET",
        requiresAuth: Bool = true,
        expectedSessionUserId: String? = nil
    ) async throws -> Data {
        try await performRawRequest(
            endpoint: endpoint,
            method: method,
            requiresAuth: requiresAuth,
            expectedSessionUserId: expectedSessionUserId,
            hasRefreshed: false
        )
    }

    private func performRawRequest(
        endpoint: String,
        method: String,
        requiresAuth: Bool,
        expectedSessionUserId: String?,
        hasRefreshed: Bool
    ) async throws -> Data {
        let requestUserId = requiresAuth
            ? (expectedSessionUserId ?? SessionStore.currentUserId)
            : nil
        if requiresAuth, requestUserId == nil {
            throw APIError.unauthorized
        }
        if let expectedSessionUserId,
           SessionStore.currentUserId != expectedSessionUserId {
            throw APIError.sessionChanged
        }
        let accessToken = requiresAuth
            ? try? KeychainManager.shared.getString(key: "jwt_access_token")
            : nil
        let base = await resolveBase()
        if let requestUserId, SessionStore.currentUserId != requestUserId {
            throw APIError.sessionChanged
        }
        if requiresAuth, accessToken == nil {
            throw APIError.unauthorized
        }
        guard let url = URL(string: "\(base)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if let accessToken {
            request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            activeBase = nil // re-check home vs internet address next time
            throw APIError.networkError(error)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        if httpResponse.statusCode == 401 && requiresAuth {
            if let requestUserId, SessionStore.currentUserId != requestUserId {
                throw APIError.sessionChanged
            }
            guard !hasRefreshed else {
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw APIError.unauthorized
            }
            switch await refreshAccessToken(expectedSessionUserId: requestUserId) {
            case .refreshed:
                return try await performRawRequest(
                    endpoint: endpoint,
                    method: method,
                    requiresAuth: requiresAuth,
                    expectedSessionUserId: requestUserId,
                    hasRefreshed: true
                )
            case .rejected:
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
                throw APIError.unauthorized
            case .unreachable:
                throw APIError.networkError(URLError(.cannotConnectToHost))
            case .sessionChanged:
                throw APIError.sessionChanged
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: "Raw HTTP Error \(httpResponse.statusCode)")
        }

        return data
    }

    private enum RefreshOutcome: Sendable {
        case refreshed
        case rejected     // server said the session is no longer valid
        case unreachable  // offline / server down: keep the session and try again later
        case sessionChanged
    }

    /// One refresh per account at a time. The server rotates refresh tokens, so parallel refreshes
    /// for the same account could make one request look like a revoked session.
    private var refreshInFlight: [String: Task<RefreshOutcome, Never>] = [:]

    private func refreshAccessToken(expectedSessionUserId: String? = nil) async -> RefreshOutcome {
        let refreshOwnerId = expectedSessionUserId ?? SessionStore.currentUserId ?? ""
        if let inFlight = refreshInFlight[refreshOwnerId] {
            return await inFlight.value
        }
        let task = Task {
            await self.performRefresh(
                expectedSessionUserId: refreshOwnerId.isEmpty ? nil : refreshOwnerId
            )
        }
        refreshInFlight[refreshOwnerId] = task
        let outcome = await task.value
        refreshInFlight.removeValue(forKey: refreshOwnerId)
        return outcome
    }

    private func performRefresh(expectedSessionUserId: String?) async -> RefreshOutcome {
        if let expectedSessionUserId,
           SessionStore.currentUserId != expectedSessionUserId {
            return .sessionChanged
        }
        guard let refreshToken = try? KeychainManager.shared.getString(key: "jwt_refresh_token") else {
            return .rejected
        }
        let base = await resolveBase()
        if let expectedSessionUserId,
           SessionStore.currentUserId != expectedSessionUserId {
            return .sessionChanged
        }
        guard let url = URL(string: "\(base)/auth/refresh") else {
            return .unreachable
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let expectedSessionUserId,
               SessionStore.currentUserId != expectedSessionUserId {
                return .sessionChanged
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unreachable
            }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return .rejected
            }
            guard httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = json["access_token"] as? String,
                  let newRefresh = json["refresh_token"] as? String else {
                return .unreachable
            }
            try? KeychainManager.shared.saveString(key: "jwt_access_token", value: newAccess)
            try? KeychainManager.shared.saveString(key: "jwt_refresh_token", value: newRefresh)
            return .refreshed
        } catch {
            return .unreachable
        }
    }
}
