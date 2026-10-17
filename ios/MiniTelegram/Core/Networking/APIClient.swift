import Foundation

public enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case serverError(statusCode: Int, message: String)
    case unauthorized
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
        case .decodingError(let err):
            return "Failed to parse response: \(err.localizedDescription)"
        case .unknown:
            return "An unexpected network error occurred"
        }
    }
}

public actor APIClient {
    public static let shared = APIClient()

    private var baseURLString: String

    public init() {
        self.baseURLString = UserDefaults.standard.string(forKey: "server_base_url") ?? "http://localhost:3000/api/v1"
    }

    public func setBaseURL(_ url: String) {
        self.baseURLString = url
        UserDefaults.standard.set(url, forKey: "server_base_url")
    }

    public func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: (any Encodable)? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        guard let url = URL(string: "\(baseURLString)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresAuth {
            if let token = try? KeychainManager.shared.getString(key: "jwt_access_token") {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
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
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.unknown
        }

        if httpResponse.statusCode == 401 && requiresAuth {
            // Attempt refresh token rotation
            let refreshed = await refreshAccessToken()
            if refreshed {
                // Retry request once with new token
                return try await self.request(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    requiresAuth: requiresAuth
                )
            } else {
                throw APIError.unauthorized
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

    private func refreshAccessToken() async -> Bool {
        guard let refreshToken = try? KeychainManager.shared.getString(key: "jwt_refresh_token"),
              let url = URL(string: "\(baseURLString)/auth/refresh") else {
            return false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return false
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newAccess = json["access_token"] as? String,
               let newRefresh = json["refresh_token"] as? String {
                try? KeychainManager.shared.saveString(key: "jwt_access_token", value: newAccess)
                try? KeychainManager.shared.saveString(key: "jwt_refresh_token", value: newRefresh)
                return true
            }
            return false
        } catch {
            return false
        }
    }
}
