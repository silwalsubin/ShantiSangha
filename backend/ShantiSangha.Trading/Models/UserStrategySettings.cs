namespace ShantiSangha.Trading.Models;

/// <summary>
/// Per-user tunable strategy constants. Defaults are seeded for the
/// "active trader" Mode D — short-horizon entry signals (1W),
/// tighter stops (-7%), +10% take-profit, modest cooldown.
///
/// One row per user; PortfolioService reads from here instead of
/// hardcoded constants so users can adjust without code changes.
/// </summary>
public class UserStrategySettings
{
    public Guid UserId { get; set; }
    public decimal StopLossPct { get; set; } = 0.07m;          // Rule 3
    public decimal TakeProfitPct { get; set; } = 0.10m;        // Rule 11
    public decimal EntryThresholdPBuy { get; set; } = 0.60m;   // Rule 10
    public string EntryHorizon { get; set; } = "1W";           // Rule 10 — "1W" | "1M" | "1Y"
    public int CooldownDays { get; set; } = 5;                 // Rule 4 (informational; not server-enforced)
    public decimal PositionCapPct { get; set; } = 0.10m;       // Rule 2
    public int MinSectors { get; set; } = 8;                   // Rule 1
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
