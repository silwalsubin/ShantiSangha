import Foundation

/// Mirrors `ShantiSangha.Trading.Contracts.TradingSignalDto`.
///
/// Top-level Action / *Score fields are the 1M view (the canonical "default
/// horizon" for any single-verdict surface). The detail screen reads from
/// `horizon1W / horizon1M / horizon1Y` to render three stacked meters.
struct TradingSignal: Codable, Identifiable, Hashable {
    let ticker: String
    let date: String                  // "yyyy-MM-dd" — calendar date the signal row was generated for
    let lastBarDate: String?          // "yyyy-MM-dd" — last EOD bar that fed the score; absent on legacy responses
    let action: String                // "Buy" | "Sell" | "Hold" — equals horizon1M.action
    let conviction: Double            // equals horizon1M.conviction
    let technicalScore: Double        // equals horizon1M.technicalScore
    let compositeScore: Double        // equals horizon1M.compositeScore
    let price: Double?
    let technicalSignals: [StrategyContribution] // equals horizon1M.technicalSignals
    let horizon1W: HorizonRead
    let horizon1M: HorizonRead
    let horizon1Y: HorizonRead

    var id: String { "\(ticker)-\(date)" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try c.decode(String.self, forKey: .ticker)
        date = try c.decode(String.self, forKey: .date)
        lastBarDate = try c.decodeIfPresent(String.self, forKey: .lastBarDate)
        action = try c.decode(String.self, forKey: .action)
        conviction = try c.decode(Double.self, forKey: .conviction)
        technicalScore = try c.decode(Double.self, forKey: .technicalScore)
        compositeScore = try c.decode(Double.self, forKey: .compositeScore)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        technicalSignals = try c.decodeArrayLenient(forKey: .technicalSignals)
        horizon1W = try c.decode(HorizonRead.self, forKey: .horizon1W)
        horizon1M = try c.decode(HorizonRead.self, forKey: .horizon1M)
        horizon1Y = try c.decode(HorizonRead.self, forKey: .horizon1Y)
    }
}

/// One horizon's read of (ticker, date) — Buy/Hold/Sell, composite, conviction,
/// and the per-strategy contributions for that horizon's weight vector.
///
/// `pBuy / pHold / pSell / expectedReturn` are populated by the post-GBM
/// scoring pipeline. Pre-GBM rows ship with `pHold = 1.0, pBuy = pSell = 0`
/// (or omit the keys entirely on legacy responses) — use
/// `hasProbabilisticVerdict` to gate UI that depends on real distributions.
struct HorizonRead: Codable, Hashable {
    let action: String                // "Buy" | "Sell" | "Hold"
    let conviction: Double
    let technicalScore: Double
    let compositeScore: Double
    let technicalSignals: [StrategyContribution]
    let pBuy: Double?
    let pHold: Double?
    let pSell: Double?
    let expectedReturn: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decode(String.self, forKey: .action)
        conviction = try c.decode(Double.self, forKey: .conviction)
        technicalScore = try c.decode(Double.self, forKey: .technicalScore)
        compositeScore = try c.decode(Double.self, forKey: .compositeScore)
        technicalSignals = try c.decodeArrayLenient(forKey: .technicalSignals)
        pBuy = try c.decodeIfPresent(Double.self, forKey: .pBuy)
        pHold = try c.decodeIfPresent(Double.self, forKey: .pHold)
        pSell = try c.decodeIfPresent(Double.self, forKey: .pSell)
        expectedReturn = try c.decodeIfPresent(Double.self, forKey: .expectedReturn)
    }

    /// True when the model returned real probabilities (post-GBM signals).
    /// Pre-GBM rows have pHold=1.0 and pBuy=pSell=0 — sum is still 1 but
    /// the distribution is degenerate; treat as "no probabilistic data".
    var hasProbabilisticVerdict: Bool {
        guard let pBuy, let pSell else { return false }
        return pBuy > 0.0 || pSell > 0.0
    }
}

private extension KeyedDecodingContainer {
    /// Decode an array field that may be missing or explicitly null on the
    /// wire, defaulting to []. Defensive against legacy server responses
    /// where a contribution list hasn't been backfilled yet.
    func decodeArrayLenient<T: Decodable>(forKey key: K) throws -> [T] {
        try decodeIfPresent([T].self, forKey: key) ?? []
    }
}

enum WiseCatHorizon: String, CaseIterable, Identifiable {
    case oneWeek  = "1W"
    case oneMonth = "1M"
    case oneYear  = "1Y"

    var id: String { rawValue }

    var label: String { rawValue }
}

extension TradingSignal {
    func read(for horizon: WiseCatHorizon) -> HorizonRead {
        switch horizon {
        case .oneWeek:  return horizon1W
        case .oneMonth: return horizon1M
        case .oneYear:  return horizon1Y
        }
    }
}

struct StrategyContribution: Codable, Hashable {
    let name: String
    let value: Double
    let contribution: Double
    let weight: Double
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
