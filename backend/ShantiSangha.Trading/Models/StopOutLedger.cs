namespace ShantiSangha.Trading.Models;

/// <summary>
/// One row per stop-out event. Written when a position is removed at or
/// below the user's stop-loss threshold (auto-detected from the last
/// cached close vs cost basis). The plan generator reads recent rows to
/// enforce Rule 4 — block BUY re-entry on a ticker still in cooldown.
/// </summary>
public class StopOutLedger
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Ticker { get; set; } = string.Empty;
    public DateTime StoppedAt { get; set; } = DateTime.UtcNow;
    public decimal ExitPrice { get; set; }       // last cached close at removal time
    public decimal CostBasis { get; set; }       // per-share cost basis on the removed position
    public decimal LossPct { get; set; }         // (exit/cost - 1); negative
}
