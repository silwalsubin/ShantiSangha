using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Shared.Interfaces;

/// <summary>
/// Pre-composed chart reading service. Lazy-generates on first read; returns
/// cached prose on subsequent reads until birth details change (detected via
/// chart hash).
/// </summary>
public interface IChartReadingService
{
    /// <summary>
    /// Returns the cached reading if the user's current chart hash matches.
    /// Returns null if no reading exists OR if the stored hash is stale.
    /// Does not trigger generation — caller is responsible for that.
    /// </summary>
    Task<ChartReading?> GetAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Composes (or recomposes) the reading from the user's current chart
    /// and upserts it. Each section is generated independently via the LLM
    /// with bounded prompts; sections that fail are stored as empty strings
    /// and logged for retry.
    /// </summary>
    Task<ChartReading> GenerateAsync(Guid userId, CancellationToken ct = default);

    /// <summary>
    /// Drops the cached reading for a user. Next GET will regenerate.
    /// </summary>
    Task InvalidateAsync(Guid userId, CancellationToken ct = default);
}
