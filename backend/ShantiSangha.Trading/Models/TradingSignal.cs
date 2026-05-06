namespace ShantiSangha.Trading.Models;

/// <summary>
/// One row per (user, ticker, date). Astro score is per-user (uses their natal
/// chart); technical score is shared but denormalized here for query speed.
/// </summary>
public class TradingSignal
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Ticker { get; set; } = string.Empty;
    public DateOnly Date { get; set; }

    public TradingAction Action { get; set; }

    /// <summary>|composite| in [0, 1]. Drives push triggering and UI prominence.</summary>
    public double Conviction { get; set; }

    public double TechnicalScore { get; set; }
    public double AstroScore { get; set; }
    public double CompositeScore { get; set; }

    /// <summary>JSON containing per-strategy contributions + per-astro-angle scores. Used by the iOS detail view.</summary>
    public string ReasoningJson { get; set; } = "{}";

    public decimal? PriceAtSignal { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
