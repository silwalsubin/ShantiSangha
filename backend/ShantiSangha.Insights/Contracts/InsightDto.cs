namespace ShantiSangha.Insights.Contracts;

public record InsightDto(
    Guid Id,
    string Content,
    Guid? SourceConversationId,
    Guid? SourceJournalId,
    DateTime CreatedAt);
