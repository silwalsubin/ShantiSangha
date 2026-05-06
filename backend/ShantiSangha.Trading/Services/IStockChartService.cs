namespace ShantiSangha.Trading.Services;

/// <summary>
/// Loads or computes a ticker's natal chart (signatures + IPO datetime).
/// Reuses ShantiSangha.Jyotish ChartSignatures as-is — a stock IPO is just
/// another DateTime + lat/lon to feed into the same engine.
/// </summary>
public interface IStockChartService
{
    Task<StockNatalChartView?> GetOrCreateAsync(string ticker, CancellationToken ct = default);
}

public record StockNatalChartView(
    string Ticker,
    DateOnly IpoDate,
    string? IpoTimeEt,
    double Latitude,
    double Longitude,
    string Exchange,
    IReadOnlyList<string> Signatures,
    DateTime IpoUtc
);
