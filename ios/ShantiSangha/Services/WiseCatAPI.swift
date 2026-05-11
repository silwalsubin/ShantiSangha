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

    static func searchSymbols(_ query: String, limit: Int = 10) async throws -> [SymbolMatch] {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await ApiService.shared.get("/wisecat/symbols/search?q=\(escaped)&limit=\(limit)")
    }

    /// Enriched search — same shape as `searchSymbols` but each row may
    /// carry `sector` + `pBuy` + `pSell` + `horizon`. Used by the in-app
    /// search bar to render filter chips and signal badges.
    static func searchSymbolsEnriched(_ query: String, limit: Int = 12) async throws -> [SymbolMatch] {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await ApiService.shared.get("/wisecat/symbols/search/enriched?q=\(escaped)&limit=\(limit)")
    }

    /// Enriched watchlist — same shape as `searchSymbolsEnriched`,
    /// pre-filtered to exclude held tickers. Powers the "Watching"
    /// section on the Stocks home view.
    static func listWatchlistEnriched() async throws -> [SymbolMatch] {
        try await ApiService.shared.get("/wisecat/watchlist/enriched")
    }

    static func getChart(_ ticker: String, range: ChartRange) async throws -> ChartHistory {
        try await ApiService.shared.get("/wisecat/chart/\(ticker)?period=\(range.rawValue)")
    }

    // ---------- Portfolio (Mode B strategy support) ------------------------

    static func listPortfolio() async throws -> [PortfolioPosition] {
        try await ApiService.shared.get("/wisecat/portfolio")
    }

    static func savePortfolio(_ positions: [SavePortfolioPosition], cashBalance: Double? = nil) async throws -> [PortfolioPosition] {
        let body = SavePortfolioRequest(positions: positions, cashBalance: cashBalance)
        return try await ApiService.shared.post("/wisecat/portfolio", body: body)
    }

    static func getPortfolioPlan(cashBalance: Double? = nil) async throws -> PortfolioPlan {
        if let cashBalance {
            return try await ApiService.shared.get("/wisecat/portfolio/plan?cash=\(cashBalance)")
        }
        return try await ApiService.shared.get("/wisecat/portfolio/plan")
    }

    static func addPortfolioPosition(_ position: SavePortfolioPosition) async throws -> PortfolioPosition {
        try await ApiService.shared.post("/wisecat/portfolio/position", body: position)
    }

    static func removePortfolioPosition(_ ticker: String) async throws {
        try await ApiService.shared.delete("/wisecat/portfolio/position/\(ticker)")
    }

    // ---------- Strategy settings (Rule constants per user) ----------------

    static func getStrategySettings() async throws -> StrategySettings {
        try await ApiService.shared.get("/wisecat/strategy/settings")
    }

    static func updateStrategySettings(_ body: UpdateStrategySettingsRequest) async throws -> StrategySettings {
        try await ApiService.shared.put("/wisecat/strategy/settings", body: body)
    }

    // ---------- Backtest preview -------------------------------------------

    static func runStrategyBacktest() async throws -> StrategyBacktestResult {
        try await ApiService.shared.post("/wisecat/strategy/backtest")
    }
}
