namespace ShantiSangha.Journal.Contracts;

public record CreateJournalRequest(string Title, string Content);

public record UpdateJournalRequest(string? Title, string? Content);

public record JournalListItem(
    Guid Id,
    string Title,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    string Preview);

public record JournalCreatedResponse(Guid Id, string Title, DateTime CreatedAt);

public record JournalDetailResponse(
    Guid Id,
    string Title,
    string Content,
    DateTime CreatedAt,
    DateTime UpdatedAt);
