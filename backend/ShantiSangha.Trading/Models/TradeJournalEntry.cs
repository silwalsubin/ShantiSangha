namespace ShantiSangha.Trading.Models;

public enum TradeJournalKind
{
    Entry = 0,         // opened a position
    Exit = 1,          // closed a position (any reason)
    Trim = 2,          // partial sell
    AddOn = 3,         // averaged up / topped up an under-weight slot
    Note = 4,          // free-form observation (no position change)
}

/// <summary>
/// Rule 8: journal every entry and exit with the reason. One row per
/// action the user wants to remember. Rendered in the Stocks tab's
/// daily-check surface and the weekly-review view.
/// </summary>
public class TradeJournalEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Ticker { get; set; } = string.Empty;
    public TradeJournalKind Kind { get; set; } = TradeJournalKind.Note;
    public decimal? Price { get; set; }
    public decimal? Shares { get; set; }
    public string? Reason { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
