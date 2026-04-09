namespace ShantiSangha.Shared.Events;

public record MessagesSavedEvent(
    Guid ConversationId,
    Guid UserId,
    int MessageCount,
    IReadOnlyList<Guid> LastMessageIds);
