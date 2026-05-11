import Foundation

/// Mirrors `ShantiSangha.Trading.Contracts.StrategySettingsDto` — the
/// user's tunable rule constants. Defaults on the server are the Mode D
/// "active trader" profile (-7% stop, +10% TP, 1W p_buy ≥ 0.60).
struct StrategySettings: Codable, Hashable {
    let stopLossPct: Double
    let takeProfitPct: Double
    let entryThresholdPBuy: Double
    let entryHorizon: String          // "1W" | "1M" | "1Y"
    let cooldownDays: Int
    let positionCapPct: Double
    let minSectors: Int
    let updatedAt: String
}

/// PUT body — every field optional; omit a field to leave it unchanged.
struct UpdateStrategySettingsRequest: Codable {
    let stopLossPct: Double?
    let takeProfitPct: Double?
    let entryThresholdPBuy: Double?
    let entryHorizon: String?
    let cooldownDays: Int?
    let positionCapPct: Double?
    let minSectors: Int?
}
