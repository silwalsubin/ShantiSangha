import Foundation

/// Wrapper around `/api/jyotish/reading/of/{subjectUserId}` — the viewer's
/// private 4-section reading of one specific subject. Lazy-generates on
/// first GET; gated by an active BirthDetailShare grant from subject to
/// viewer. 403 means the share isn't (or no longer is) in place.
enum PairChartReadingAPI {
    struct Reading: Decodable {
        let sections: [String: String]
        // Backend serializes ISO-8601; the shared ApiService decoder doesn't
        // configure a custom date strategy, so the existing chart-reading
        // response keeps this as a string and we mirror that.
        let generatedAt: String
        let isComplete: Bool
    }

    static func get(of subjectUserId: UUID, force: Bool = false) async throws -> Reading {
        var path = "/jyotish/reading/of/\(subjectUserId.uuidString.lowercased())"
        if force { path += "?force=true" }
        return try await ApiService.shared.get(path)
    }

    static func invalidate(of subjectUserId: UUID) async throws {
        try await ApiService.shared.delete(
            "/jyotish/reading/of/\(subjectUserId.uuidString.lowercased())")
    }
}
