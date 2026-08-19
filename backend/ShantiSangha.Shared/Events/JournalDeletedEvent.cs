namespace ShantiSangha.Shared.Events;

public record JournalDeletedEvent(Guid JournalId, Guid UserId);
