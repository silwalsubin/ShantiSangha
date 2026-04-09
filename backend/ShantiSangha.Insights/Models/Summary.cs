namespace ShantiSangha.Insights.Models;

public enum SummarySourceType { Conversation, Journal }

public class Summary
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public SummarySourceType SourceType { get; set; }
    public Guid? ConversationId { get; set; }
    public Guid? JournalId { get; set; }
    public string Content { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
}
