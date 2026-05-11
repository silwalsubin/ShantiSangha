namespace ShantiSangha.Trading.Models;

/// <summary>
/// Global cache of ticker → sector mappings. Populated lazily when a
/// portfolio plan asks about a ticker we don't have hardcoded. Shared
/// across users (sector is a property of the issuer, not the holder).
/// </summary>
public class TickerSector
{
    public string Ticker { get; set; } = string.Empty;
    public string Sector { get; set; } = string.Empty;  // "Unknown" if resolution failed
    public string? Name { get; set; }                    // best-effort issuer name
    public DateTime FetchedAt { get; set; } = DateTime.UtcNow;
}
