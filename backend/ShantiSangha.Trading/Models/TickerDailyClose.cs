namespace ShantiSangha.Trading.Models;

/// <summary>
/// Cached daily OHLCV bar. Shared across users — fetched once per ticker per
/// trading day from Finnhub via the Python service, then never re-fetched.
/// </summary>
public class TickerDailyClose
{
    public string Ticker { get; set; } = string.Empty;
    public DateOnly Date { get; set; }
    public decimal Open { get; set; }
    public decimal High { get; set; }
    public decimal Low { get; set; }
    public decimal Close { get; set; }
    public long Volume { get; set; }
}
