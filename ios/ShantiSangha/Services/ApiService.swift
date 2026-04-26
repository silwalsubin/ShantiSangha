import Foundation

/// HTTP client for the ShantiSangha API.
/// Mirrors frontend/src/composables/useApi.ts
///
/// All API calls go through this service. Automatically attaches
/// the Firebase session token for authenticated requests.
///
/// Token caching: Firebase getIDToken() hits the network when the token
/// is expired (~every 60 min). We cache the result for 50 minutes so
/// that the majority of requests never block on a network call inside
/// the actor — avoiding the serialization bottleneck where one slow
/// token refresh queues up every subsequent API call.
actor ApiService {
    static let shared = ApiService()

    private let baseURL: String
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let session: URLSession
    private var tokenProvider: (() async -> String?)?

    // Token cache — avoids blocking every request on Firebase network calls
    private var cachedToken: String?
    private var cachedTokenExpiry: Date = .distantPast
    private static let tokenCacheDuration: TimeInterval = 50 * 60 // 50 min (tokens last 60)

    init(baseURL: String = "https://shantisangha.com/api") {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func setTokenProvider(_ provider: @escaping () async -> String?) {
        self.tokenProvider = provider
    }

    /// Exposed so non-HTTP transports (the chat WebSocket) can build a
    /// URL against the same origin without duplicating config.
    func getBaseURL() -> String { baseURL }

    /// Resolve a fresh (cache-aware) bearer token. Used by the chat
    /// WebSocket which puts the token in `?token=` because the upgrade
    /// handshake doesn't accept arbitrary headers.
    func currentToken() async -> String? {
        await resolveToken()
    }

    /// Invalidate the cached token (e.g. on sign-out).
    func clearTokenCache() {
        cachedToken = nil
        cachedTokenExpiry = .distantPast
    }

    // MARK: - HTTP Methods

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path: path)
    }

    func post<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        try await request("POST", path: path, body: body)
    }

    func patch<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        try await request("PATCH", path: path, body: body)
    }

    func put<T: Decodable>(_ path: String, body: Encodable? = nil) async throws -> T {
        try await request("PUT", path: path, body: body)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request("DELETE", path: path)
    }

    /// DELETE that decodes a response body. Used by soft-delete endpoints
    /// that return the updated row (with `deletedAt` set) so the caller
    /// can update local state without a follow-up fetch.
    func deleteReturning<T: Decodable>(_ path: String) async throws -> T {
        try await request("DELETE", path: path)
    }

    /// POST with raw Data body (for sync queue)
    func postRaw<T: Decodable>(_ path: String, body: Data) async throws -> T {
        try await requestRaw("POST", path: path, body: body)
    }

    /// PATCH with raw Data body (for sync queue)
    func patchRaw<T: Decodable>(_ path: String, body: Data) async throws -> T {
        try await requestRaw("PATCH", path: path, body: body)
    }

    // MARK: - Token

    private func resolveToken() async -> String? {
        // Return cached token if still fresh
        if let cached = cachedToken, Date() < cachedTokenExpiry {
            return cached
        }

        // Fetch fresh token from Firebase
        let token = await tokenProvider?()
        if let token {
            cachedToken = token
            cachedTokenExpiry = Date().addingTimeInterval(Self.tokenCacheDuration)
        }
        return token
    }

    // MARK: - Internal

    private func request<T: Decodable>(_ method: String, path: String, body: Encodable? = nil) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ApiError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await resolveToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        // Retry GET requests once on timeout (common after app resumes from background)
        let isRetryable = method == "GET"
        do {
            return try await execute(req)
        } catch let error as ApiError where isRetryable && error.is401 {
            // 401 cleared the cached token — retry with a fresh one
            if let token = await resolveToken() {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            await AppLogger.shared.info("API", "Retrying \(method) \(path) after 401")
            return try await execute(req)
        } catch let error as URLError where isRetryable && error.code == .timedOut {
            await AppLogger.shared.info("API", "Retrying \(method) \(path) after timeout")
            return try await execute(req)
        }
    }

    private func requestRaw<T: Decodable>(_ method: String, path: String, body: Data) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ApiError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await resolveToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        req.httpBody = body

        let isRetryable = method == "GET"
        do {
            return try await execute(req)
        } catch let error as ApiError where isRetryable && error.is401 {
            if let token = await resolveToken() {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            await AppLogger.shared.info("API", "Retrying \(req.httpMethod ?? "?") \(path) after 401")
            return try await execute(req)
        } catch let error as URLError where isRetryable && error.code == .timedOut {
            await AppLogger.shared.info("API", "Retrying \(req.httpMethod ?? "?") \(path) after timeout")
            return try await execute(req)
        }
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ApiError.invalidResponse
        }

        // If we get a 401, the cached token may be stale — clear it so the
        // next request fetches a fresh one from Firebase.
        if http.statusCode == 401 {
            cachedToken = nil
            cachedTokenExpiry = .distantPast
        }

        guard (200...299).contains(http.statusCode) else {
            throw ApiError.httpError(statusCode: http.statusCode, data: data)
        }

        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }

        return try decoder.decode(T.self, from: data)
    }
}

struct EmptyResponse: Decodable, Sendable {}

enum ApiError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data)

    var is401: Bool {
        if case .httpError(statusCode: 401, _) = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .httpError(let code, _): return "HTTP error \(code)"
        }
    }
}
