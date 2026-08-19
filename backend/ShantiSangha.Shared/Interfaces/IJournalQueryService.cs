using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IJournalQueryService
{
    Task<JournalContentDto?> GetJournalContentAsync(Guid journalId, CancellationToken ct = default);

    /// All journal ids across all users — used by the Memory module's one-time
    /// backfill. Fine at current scale; page it if journals ever number 100K+.
    Task<IReadOnlyList<Guid>> GetAllJournalIdsAsync(CancellationToken ct = default);
}
