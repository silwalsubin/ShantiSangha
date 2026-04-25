namespace ShantiSangha.Shared.Events;

public record GoalCheckedInEvent(Guid UserId, DateOnly Date, bool Completed);
