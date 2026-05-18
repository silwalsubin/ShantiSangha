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

/// Action kinds mirror PortfolioActionKind enum on the server. The API
/// project registers `JsonStringEnumConverter`, so enums come across the
/// wire as their literal C# names ("Sell", "Trim", "Buy", "Hold") — not
/// as integers. These raw values must match.
enum PortfolioActionKind: String, Codable, Hashable {
    case sell = "Sell"
    case trim = "Trim"
    case buy  = "Buy"
    case hold = "Hold"

    var label: String {
        switch self {
        case .sell: return "SELL"
        case .trim: return "TRIM"
        case .buy:  return "BUY"
        case .hold: return "HOLD"
        }
    }
}

/// Concrete numbers for placing a bracket order at the broker. Populated
/// on BUY actions only; null on Sell/Trim/Hold.
struct BracketOrder: Codable, Hashable {
    let entryPrice: Double
    let stopPrice: Double
    let targetPrice: Double
    let riskPerShare: Double
    let totalRiskDollars: Double
    let rMultiple: Double
}

struct PortfolioAction: Codable, Identifiable, Hashable {
    let ticker: String
    let sector: String
    let kind: PortfolioActionKind
    let shares: Double?
    let price: Double?
    let amount: Double?
    let reason: String
    let bracket: BracketOrder?

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
    let pBuy: Double
    let pSell: Double

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

// MARK: - IBKR broker link

/// Mirrors IbkrStatusDto on the .NET side. `status` is one of
/// "Active", "NeedsReauth", "Disconnected", "Suspended". When Active,
/// manual add/remove is blocked server-side and the iOS UI should hide
/// those affordances. Cash + positions are sourced from the broker.
struct IbkrStatus: Codable, Equatable {
    let status: String
    let ibkrAccountId: String?
    let linkedAt: String?
    let lastSyncAt: String?
    let lastSuccessfulSyncAt: String?
    let lastErrorMessage: String?
    let baseCurrency: String
    let cashBalance: Double
    let cashBalanceAt: String?

    var isLinked: Bool { status == "Active" }
    var needsReauth: Bool { status == "NeedsReauth" }
}

struct IbkrSyncResult: Codable {
    let success: Bool
    let positionsImported: Int
    let positionsSkipped: Int
    let cashBalance: Double
    let baseCurrency: String
    let status: String
    let errorMessage: String?
}
