import Foundation

/// Mirrors `ShantiSangha.Trading.Contracts.StrategyBacktestResultDto`.
/// Returned by the Rules-sheet "Preview backtest envelope" button.
struct StrategyBacktestResult: Codable, Hashable {
    let window: String
    let annualizedReturnPct: Double
    let maxDrawdownPct: Double
    let trades: Int
    let winRatePct: Double
    let sharpeApprox: Double
    let notes: String
}
