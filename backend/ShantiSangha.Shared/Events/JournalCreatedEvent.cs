namespace ShantiSangha.Shared.Events;

public record JournalCreatedEvent(Guid JournalId, Guid UserId);
