using ShantiSangha.Journal.Contracts;

namespace ShantiSangha.Journal.Services;

public interface IJournalService
{
    Task<IReadOnlyList<JournalListItem>> ListAsync(Guid userId, int page, int pageSize, CancellationToken ct = default);
    Task<JournalCreatedResponse> CreateAsync(Guid userId, CreateJournalRequest request, CancellationToken ct = default);
    Task<JournalDetailResponse?> GetByIdAsync(Guid id, Guid userId, CancellationToken ct = default);
    Task<bool> UpdateAsync(Guid id, Guid userId, UpdateJournalRequest request, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, Guid userId, CancellationToken ct = default);
}
