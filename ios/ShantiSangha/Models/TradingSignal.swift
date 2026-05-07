import Foundation

/// Mirrors `ShantiSangha.Trading.Contracts.TradingSignalDto`.
struct TradingSignal: Codable, Identifiable, Hashable {
    let ticker: String
    let date: String                  // "yyyy-MM-dd"
    let action: String                // "Buy" | "Sell" | "Hold"
    let conviction: Double
    let technicalScore: Double
    let astroScore: Double
    let compositeScore: Double
    let price: Double?
    let technicalSignals: [StrategyContribution]
    let astroAngles: [AstroAngleScore]

    var id: String { "\(ticker)-\(date)" }
}

struct StrategyContribution: Codable, Hashable {
    let name: String
    let value: Double
    let contribution: Double
    let weight: Double
}

struct AstroAngleScore: Codable, Hashable {
    let angle: String                 // "user_natal" | "panchang" | "stock_natal"
    let score: Double
    let highlights: [String]
}

struct WatchlistEntry: Codable, Identifiable, Hashable {
    let ticker: String
    let addedAt: String

    var id: String { ticker }
}

struct SymbolMatch: Codable, Identifiable, Hashable {
    let symbol: String
    let description: String
    let type: String

    var id: String { symbol }
}

enum WiseCatAction: String {
    case buy = "Buy"
    case sell = "Sell"
    case hold = "Hold"

    static func from(_ raw: String) -> WiseCatAction {
        WiseCatAction(rawValue: raw) ?? .hold
    }
}
