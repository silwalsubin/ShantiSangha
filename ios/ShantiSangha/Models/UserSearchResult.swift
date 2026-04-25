import Foundation

/// Mirror of the backend `UserSearchResult` — one row in a user-search response.
struct UserSearchResult: Codable, Identifiable, Equatable {
    let userId: UUID
    let displayName: String
    let country: String?
    let state: String?
    let city: String?
    let avatarKey: String?
    let avatarUrl: String?

    var id: UUID { userId }

    /// Human-readable location string for list rows. Strips empty fields and
    /// joins what's left with commas. Returns nil when nothing is set so the
    /// row can omit the location line entirely instead of showing a stray
    /// comma or "Unknown".
    var locationString: String? {
        let parts = [city, state, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Mirror of the backend `UserSearchPage`.
struct UserSearchPage: Codable, Equatable {
    let page: Int
    let pageSize: Int
    let totalCount: Int
    let hasMore: Bool
    let results: [UserSearchResult]
}
