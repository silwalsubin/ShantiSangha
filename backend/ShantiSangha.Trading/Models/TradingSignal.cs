namespace ShantiSangha.Trading.Models;

/// <summary>
/// One row per (user, ticker, date). Carries three verdicts side by side —
/// 1W / 1M / 1Y — plus the legacy single-horizon columns (Action, Conviction,
/// CompositeScore, TechnicalScore) which mirror the 1M values for back-compat
/// with consumers that haven't migrated to the per-horizon API.
/// </summary>
public class TradingSignal
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Ticker { get; set; } = string.Empty;
    public DateOnly Date { get; set; }

    /// <summary>
    /// Date of the most recent EOD bar that fed this score. Surfaced on the
    /// iOS detail view as "as of {LastBarDate}" so users understand why the
    /// gauge doesn't tick with the live chart — scores reflect last close.
    /// On weekends / holidays this lags `Date` by 1–3 days.
    /// </summary>
    public DateOnly LastBarDate { get; set; }

    // Legacy single-horizon columns — kept in lockstep with the 1M values.
    public TradingAction Action { get; set; }
    public double Conviction { get; set; }
    public double TechnicalScore { get; set; }
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

    public double Composite1W { get; set; }
    public double Composite1M { get; set; }
    public double Composite1Y { get; set; }

    /// <summary>
    /// Probabilistic verdict from the GBM (LightGBM) classifier — one
    /// (pBuy, pHold, pSell) triple plus an expected forward return per
    /// horizon. The triple sums to 1.0 when populated by a real model
    /// run; on legacy rows (pre-GBM, pre-migration) and on Lambda
    /// responses that omit the keys, PHold defaults to 1.0 and the
    /// other three default to 0.0 so the verdict reads as "fully Hold"
    /// until the model is trained.
    /// </summary>
    public double PBuy1W { get; set; }
    public double PHold1W { get; set; } = 1.0;
    public double PSell1W { get; set; }
    public double ExpectedReturn1W { get; set; }

    public double PBuy1M { get; set; }
    public double PHold1M { get; set; } = 1.0;
    public double PSell1M { get; set; }
    public double ExpectedReturn1M { get; set; }

    public double PBuy1Y { get; set; }
    public double PHold1Y { get; set; } = 1.0;
    public double PSell1Y { get; set; }
    public double ExpectedReturn1Y { get; set; }

    /// <summary>JSON containing per-horizon technical contributions. Used by the iOS detail view.</summary>
    public string ReasoningJson { get; set; } = "{}";

    public decimal? PriceAtSignal { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
