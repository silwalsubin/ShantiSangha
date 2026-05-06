namespace ShantiSangha.Trading.Models;

/// <summary>
/// IPO/incorporation chart for a ticker, treating the stock like a person.
/// Shared across all users — a stock's natal chart is the same for everyone.
/// Populated on first watchlist add (or seeded from the curated CSV at startup).
/// </summary>
public class StockNatalChart
{
    public string Ticker { get; set; } = string.Empty;
    public DateOnly IpoDate { get; set; }

    /// <summary>HH:mm in ET. Null when first-trade time isn't known; we fall back to 09:30.</summary>
    public string? IpoTimeEt { get; set; }
    public double IpoLatitude { get; set; }
    public double IpoLongitude { get; set; }
    public string Exchange { get; set; } = string.Empty;

    /// <summary>JSON array of natal signatures (e.g. "sun_in_makara"). Cached to avoid recomputation.</summary>
    public string SignaturesJson { get; set; } = "[]";

    public DateTime ComputedAt { get; set; } = DateTime.UtcNow;
}
