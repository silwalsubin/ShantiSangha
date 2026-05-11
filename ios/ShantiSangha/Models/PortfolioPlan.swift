import Foundation

// Mirrors ShantiSangha.Trading.Contracts.PortfolioContracts on the server.

/// A single position in the user's portfolio (server-side row).
struct PortfolioPosition: Codable, Identifiable, Hashable {
    let ticker: String
    let shares: Double
    let costBasis: Double
    let updatedAt: String?

    var id: String { ticker }
}

/// Body shape for POST /api/wisecat/portfolio — full replacement.
struct SavePortfolioPosition: Codable, Hashable {
    let ticker: String
    let shares: Double
    let costBasis: Double
}

struct SavePortfolioRequest: Codable {
    let positions: [SavePortfolioPosition]
    let cashBalance: Double?
}

/// Action kinds mirror PortfolioActionKind enum on the server.
/// The server emits them as integers — keep these raw values aligned.
enum PortfolioActionKind: Int, Codable, Hashable {
    case sell = 0
    case trim = 1
    case buy  = 2
    case hold = 3

    var label: String {
        switch self {
        case .sell: return "SELL"
        case .trim: return "TRIM"
        case .buy:  return "BUY"
        case .hold: return "HOLD"
        }
    }
}

struct PortfolioAction: Codable, Identifiable, Hashable {
    let ticker: String
    let sector: String
    let kind: PortfolioActionKind
    let shares: Double?
    let price: Double?
    let amount: Double?
    let reason: String

    var id: String { "\(kind.rawValue)-\(ticker)" }
}

struct PortfolioHolding: Codable, Identifiable, Hashable {
    let ticker: String
    let sector: String
    let shares: Double
    let costBasis: Double
    let currentPrice: Double
    let marketValue: Double
    let percentOfPortfolio: Double
    let unrealizedReturnPct: Double
    let pBuy1M: Double
    let pSell1M: Double

    var id: String { ticker }
}

struct SectorAllocation: Codable, Hashable {
    let sector: String
    let marketValue: Double
    let percentOfPortfolio: Double
}

struct PortfolioPlan: Codable {
    let generatedAt: String
    let totalValue: Double
    let investedValue: Double
    let cashBalance: Double
    let positionCount: Int
    let sectorsCovered: Int
    let minSectorsRequired: Int
    let missingSectors: [String]
    let holdings: [PortfolioHolding]
    let sectorBreakdown: [SectorAllocation]
    let actions: [PortfolioAction]
}
