namespace ShantiSangha.Shared.Events;

public record JournalUpdatedEvent(Guid JournalId, Guid UserId);
