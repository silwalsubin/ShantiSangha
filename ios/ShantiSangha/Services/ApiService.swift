import Foundation

/// HTTP client for the ShantiSangha API.
/// Mirrors frontend/src/composables/useApi.ts
///
/// All API calls go through this service. Automatically attaches
/// the Clerk session token for authenticated requests.
actor ApiService {
    static let shared = ApiService()

    private let baseURL: String
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private var tokenProvider: (() async -> String?)?

    init(baseURL: String = "https://shantisangha.com/api") {
        self.baseURL = baseURL
    }

    func setTokenProvider(_ provider: @escaping () async -> String?) {
        self.tokenProvider = provider
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

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request("DELETE", path: path)
    }

    // MARK: - Internal

    private func request<T: Decodable>(_ method: String, path: String, body: Encodable? = nil) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ApiError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = await tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ApiError.invalidResponse
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

nonisolated struct EmptyResponse: Decodable, Sendable {}

enum ApiError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, data: Data)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .httpError(let code, _): return "HTTP error \(code)"
        }
    }
}
