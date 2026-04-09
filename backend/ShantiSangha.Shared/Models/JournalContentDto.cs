namespace ShantiSangha.Shared.Models;

public record JournalContentDto(
    Guid Id,
    Guid UserId,
    string Title,
    string Content,
    DateTime CreatedAt);
