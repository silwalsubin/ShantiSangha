using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

public interface IJournalQueryService
{
    Task<JournalContentDto?> GetJournalContentAsync(Guid journalId, CancellationToken ct = default);
}
