import Foundation

/// Typed wrapper around `ApiService` for the user-search endpoint.
/// Mirrors the backend `UserSearchController` at `/api/users/search`.
enum UserSearchAPI {
    static func search(
        query: String?,
        location: String?,
        page: Int,
        pageSize: Int = 20
    ) async throws -> UserSearchPage {
        var components = URLComponents()
        components.path = "/users/search"
        var items: [URLQueryItem] = []
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let location, !location.isEmpty {
            items.append(URLQueryItem(name: "location", value: location))
        }
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "pageSize", value: String(pageSize)))
        components.queryItems = items

        // ApiService.get takes a path string; rebuild it from components.
        // `percentEncodedQuery` keeps multibyte characters and spaces encoded
        // correctly (unlike string concatenation, which would drop them).
        let path = components.path + "?" + (components.percentEncodedQuery ?? "")
        return try await ApiService.shared.get(path)
    }
}
