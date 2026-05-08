using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Shared.Interfaces;

/// <summary>
/// Composes a viewer's private 4-section reading of a specific subject from
/// the viewer's POV. Asymmetric — the same chart pair produces a different
/// reading for each side because each reads through their own chart.
/// Access is gated upstream by an active BirthDetailShare grant from
/// subject to viewer; this service trusts the gate has been checked.
/// Implementation lives in the Jyotish module; the interface is in Shared
/// so Friends can invalidate the reading when the underlying share is
/// revoked.
/// </summary>
public interface IPairChartReadingService
{
    Task<PairChartReading?> GetAsync(Guid viewerUserId, Guid subjectUserId, CancellationToken ct = default);
    Task<PairChartReading> GenerateAsync(Guid viewerUserId, Guid subjectUserId, CancellationToken ct = default);
    Task InvalidateAsync(Guid viewerUserId, Guid subjectUserId, CancellationToken ct = default);
}
