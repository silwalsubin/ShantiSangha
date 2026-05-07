namespace ShantiSangha.Trading.Models;

/// <summary>
/// One row per (user, ticker, date). Astro score is per-user (uses their natal
/// chart); technical score is shared but denormalized here for query speed.
///
/// Each row carries three verdicts side by side — 1W / 1M / 1Y — plus the
/// legacy single-horizon columns (`Action`, `Conviction`, `CompositeScore`,
/// `TechnicalScore`, `AstroScore`) which mirror the 1M values for back-compat
/// with consumers that haven't migrated to the per-horizon API.
/// </summary>
public class TradingSignal
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Ticker { get; set; } = string.Empty;
    public DateOnly Date { get; set; }

    // Legacy single-horizon columns — kept in lockstep with the 1M values.
    public TradingAction Action { get; set; }
    public double Conviction { get; set; }
    public double TechnicalScore { get; set; }
    public double AstroScore { get; set; }
    public double CompositeScore { get; set; }

    // Per-horizon verdicts.
    public TradingAction Action1W { get; set; }
    public TradingAction Action1M { get; set; }
    public TradingAction Action1Y { get; set; }

    public double Conviction1W { get; set; }
    public double Conviction1M { get; set; }
    public double Conviction1Y { get; set; }

    public double Technical1W { get; set; }
    public double Technical1M { get; set; }
    public double Technical1Y { get; set; }

    public double Astro1W { get; set; }
    public double Astro1M { get; set; }
    public double Astro1Y { get; set; }

    public double Composite1W { get; set; }
    public double Composite1M { get; set; }
    public double Composite1Y { get; set; }

    /// <summary>JSON containing per-horizon technical contributions + per-astro-angle scores. Used by the iOS detail view.</summary>
    public string ReasoningJson { get; set; } = "{}";

    public decimal? PriceAtSignal { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
