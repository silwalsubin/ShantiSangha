import Foundation

/// Wrapper around `/api/friends/birth-details-share`. The backend keys the
/// directional grant on (grantor, grantee). The current user is always the
/// grantor side of grant/revoke; the grantee userId comes from the friend's
/// linked Person.
enum BirthDetailSharesAPI {
    struct MyShares: Decodable {
        /// User IDs I have shared my birth chart with.
        let grantedTo: [UUID]
        /// User IDs that have shared their birth chart with me.
        let receivedFrom: [UUID]
    }

    struct GrantResult: Decodable {
        /// "granted" if a new share was created, "unchanged" if it already existed.
        let action: String
    }

    static func myShares() async throws -> MyShares {
        try await ApiService.shared.get("/friends/birth-details-share")
    }

    static func grant(to granteeUserId: UUID) async throws -> GrantResult {
        try await ApiService.shared.put(
            "/friends/birth-details-share/\(granteeUserId.uuidString.lowercased())")
    }

    static func revoke(from granteeUserId: UUID) async throws {
        try await ApiService.shared.delete(
            "/friends/birth-details-share/\(granteeUserId.uuidString.lowercased())")
    }
}
