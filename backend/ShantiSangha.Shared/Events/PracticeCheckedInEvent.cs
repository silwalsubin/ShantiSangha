namespace ShantiSangha.Shared.Events;

public record PracticeCheckedInEvent(Guid UserId, DateOnly Date, bool Completed);
