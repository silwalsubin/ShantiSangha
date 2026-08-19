namespace ShantiSangha.Shared.Models;

public record ChatMessageDto(
    Guid Id,
    Guid ConversationId,
    string Role,
    string Content,
    DateTime CreatedAt);
