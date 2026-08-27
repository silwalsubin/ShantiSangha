namespace ShantiSangha.Shared.Models;

public record ConversationSummary(
    Guid Id,
    string? Title,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    string LastMessage);
