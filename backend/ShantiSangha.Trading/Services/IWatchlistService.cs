using ShantiSangha.Trading.Contracts;

namespace ShantiSangha.Trading.Services;

public interface IWatchlistService
{
    Task<IReadOnlyList<WatchlistItemDto>> ListAsync(Guid userId, CancellationToken ct = default);
    Task<WatchlistItemDto> AddAsync(Guid userId, string ticker, CancellationToken ct = default);
    Task<bool> RemoveAsync(Guid userId, string ticker, CancellationToken ct = default);
}
