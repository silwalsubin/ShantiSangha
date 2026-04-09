namespace ShantiSangha.Shared.Events;

public record SafetyEventOccurredEvent(
    Guid UserId,
    string EventType,
    string? TriggerContent,
    string? Details,
    Guid? ConversationId);
