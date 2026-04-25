namespace ShantiSangha.Shared.Interfaces;

public record PracticeStatusSnapshot(
    bool CheckedInToday,
    int CurrentStreak,
    DateOnly? LastActiveDate);

/// <summary>
/// Aggregated practice status for a user. The shape is deliberately narrow —
/// returning a structured snapshot (rather than per-goal detail) prevents the
/// Friends module from ever seeing individual goal data, by construction.
/// See docs/design-principles/privacy.md "The Friends exception".
/// </summary>
public interface IPracticeStatusQueryService
{
    Task<PracticeStatusSnapshot> GetStatusAsync(
        Guid userId,
        DateOnly? localDate = null,
        CancellationToken ct = default);
}
