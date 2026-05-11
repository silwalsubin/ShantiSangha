using ShantiSangha.Trading.Contracts;

namespace ShantiSangha.Trading.Services;

public interface IJournalService
{
    Task<IReadOnlyList<JournalEntryDto>> ListAsync(
        Guid userId, int limit = 50, CancellationToken ct = default);

    Task<JournalEntryDto> CreateAsync(
        Guid userId, CreateJournalEntryRequest req, CancellationToken ct = default);

    Task<bool> DeleteAsync(Guid userId, Guid id, CancellationToken ct = default);
}
