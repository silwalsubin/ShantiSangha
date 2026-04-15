namespace ShantiSangha.Wellness.Models;

/// <summary>
/// One AI-generated journal prompt per user per day, cached so repeated
/// opens of the journal editor show the same suggestion.
/// </summary>
public class DailyJournalPrompt
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public DateOnly Date { get; set; }
    public string Content { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
