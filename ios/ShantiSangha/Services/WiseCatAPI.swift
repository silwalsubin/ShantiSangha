import Foundation

/// Typed wrapper around `ApiService` for the Wise Cat (`/api/wisecat`) endpoints.
enum WiseCatAPI {
    static func listWatchlist() async throws -> [WatchlistEntry] {
        try await ApiService.shared.get("/wisecat/watchlist")
    }

    struct AddBody: Encodable { let ticker: String }
    static func addWatchlist(_ ticker: String) async throws -> WatchlistEntry {
        try await ApiService.shared.post("/wisecat/watchlist", body: AddBody(ticker: ticker))
    }

    static func removeWatchlist(_ ticker: String) async throws {
        try await ApiService.shared.delete("/wisecat/watchlist/\(ticker)")
    }

    static func getSignals() async throws -> [TradingSignal] {
        try await ApiService.shared.get("/wisecat/signals")
    }

    static func getSignal(_ ticker: String) async throws -> TradingSignal {
        try await ApiService.shared.get("/wisecat/signals/\(ticker)")
    }
}
