namespace ShantiSangha.Chat.Contracts;

public record ConversationListItemDto(
    Guid Id,
    string? Title,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    string? LastMessage);

public record ConversationDetailDto(
    Guid Id,
    string? Title,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    IReadOnlyList<MessageDto> Messages);

public record ConversationCreatedDto(
    Guid Id,
    DateTime CreatedAt);

public record MessageDto(
    Guid Id,
    string Role,
    string Content,
    DateTime CreatedAt);
