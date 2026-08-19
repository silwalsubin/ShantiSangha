namespace ShantiSangha.Shared.Events;

public record ConversationDeletedEvent(Guid ConversationId, Guid UserId);
