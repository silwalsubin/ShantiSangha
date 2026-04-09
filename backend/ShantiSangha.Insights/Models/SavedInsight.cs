using Pgvector;

namespace ShantiSangha.Insights.Models;

public class SavedInsight
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Content { get; set; } = string.Empty;
    public Vector? Embedding { get; set; }
    public Guid? SourceConversationId { get; set; }
    public Guid? SourceJournalId { get; set; }
    public DateTime CreatedAt { get; set; }
}
