import Foundation

/// Typed wrapper around `ApiService` for the Wise Cat (`/api/wisecat`) endpoints.
enum WiseCatAPI {
    static func getSignals() async throws -> [TradingSignal] {
        try await ApiService.shared.get("/wisecat/signals")
    }

    static func getSignal(_ ticker: String) async throws -> TradingSignal {
        try await ApiService.shared.get("/wisecat/signals/\(ticker)")
    }

    static func getChart(_ ticker: String, range: ChartRange) async throws -> ChartHistory {
        try await ApiService.shared.get("/wisecat/chart/\(ticker)?period=\(range.rawValue)")
    }

    // ---------- Portfolio (Mode B strategy support) ------------------------

    static func listPortfolio() async throws -> [PortfolioPosition] {
        try await ApiService.shared.get("/wisecat/portfolio")
    }

    static func getPortfolioPlan(cashBalance: Double? = nil) async throws -> PortfolioPlan {
        if let cashBalance {
            return try await ApiService.shared.get("/wisecat/portfolio/plan?cash=\(cashBalance)")
        }
        return try await ApiService.shared.get("/wisecat/portfolio/plan")
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

    // ---------- IBKR broker link -------------------------------------------

    static func getIbkrStatus() async throws -> IbkrStatus {
        try await ApiService.shared.get("/wisecat/ibkr/status")
    }

    static func linkIbkr() async throws -> IbkrSyncResult {
        try await ApiService.shared.post("/wisecat/ibkr/link")
    }

    static func resyncIbkr() async throws -> IbkrSyncResult {
        try await ApiService.shared.post("/wisecat/ibkr/resync")
    }

    static func unlinkIbkr() async throws {
        try await ApiService.shared.delete("/wisecat/ibkr/unlink")
    }
}
