import Foundation

/// Mirrors `ShantiSangha.Trading.Contracts.JournalEntryDto`. One row per
/// entry/exit/note the user wants to remember. Rendered in the Daily-check
/// view on the Stocks tab (Rule 8 surface).
struct TradeJournalEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let ticker: String
    let kind: String          // "Entry" | "Exit" | "Trim" | "AddOn" | "Note"
    let price: Double?
    let shares: Double?
    let reason: String?
    let createdAt: String
}

struct CreateJournalEntryRequest: Codable {
    let ticker: String
    let kind: String
    let price: Double?
    let shares: Double?
    let reason: String?
}

/// Mirrors `ShantiSangha.Trading.Contracts.StrategyBacktestResultDto`.
struct StrategyBacktestResult: Codable, Hashable {
    let window: String
    let annualizedReturnPct: Double
    let maxDrawdownPct: Double
    let trades: Int
    let winRatePct: Double
    let sharpeApprox: Double
    let notes: String
}
