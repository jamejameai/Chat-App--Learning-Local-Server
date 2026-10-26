import Foundation

/// Chooses which server address to talk to.
///
/// The home-network address is tried first (fast, and works even if the internet is down).
/// If the phone is away from home, the internet (Cloudflare tunnel) address that the app
/// learned earlier from the server is used instead.
enum ServerReachability {
    static let publicURLKey = "public_server_url"
    static let activeURLKey = "active_server_url"

    /// Candidate addresses in priority order, without blanks, trailing slashes or duplicates:
    /// the primary address, then the local Bonjour and Wi-Fi IP addresses, then the internet
    /// address learned from the server, then the seed internet address built into this app.
    static func candidates(
        primary: String,
        localBonjourURL: String? = nil,
        localIPURL: String? = nil,
        publicURL: String? = nil,
        seedPublicURL: String? = nil
    ) -> [String] {
        var seen = Set<String>()
        return [primary, localBonjourURL, localIPURL, publicURL, seedPublicURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The first candidate for which `probe` succeeds, or nil if none respond.
    static func firstReachable(in candidates: [String], probe: (String) async -> Bool) async -> String? {
        for candidate in candidates where await probe(candidate) {
            return candidate
        }
        return nil
    }

    /// True only if `base` answers `/health` with the Our Chat server's `{"status":"ok"}`.
    static func probeHealth(_ base: String, timeout: TimeInterval = 2.5, session: URLSession = .shared) async -> Bool {
        guard let url = URL(string: "\(base)/health") else { return false }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return false
        }
        return String(data: data, encoding: .utf8)?.contains("\"status\":\"ok\"") ?? false
    }

    /// Asks the server for its internet address and remembers it, so the app keeps working
    /// after the phone leaves the home network. Only https addresses are accepted.
    static func learnPublicURL(
        from base: String,
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) async {
        struct NetworkConfig: Decodable { let public_url: String? }
        guard let url = URL(string: "\(base)/network/config") else { return }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let config = try? JSONDecoder().decode(NetworkConfig.self, from: data),
              let publicURL = config.public_url,
              publicURL.hasPrefix("https://"),
              URL(string: publicURL) != nil else {
            return
        }
        defaults.set(publicURL, forKey: publicURLKey)
    }
}
