using Microsoft.EntityFrameworkCore;
using ShantiSangha.Trading.Contracts;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public class WatchlistService(TradingDbContext db, IStockChartService stockChart) : IWatchlistService
{
    public async Task<IReadOnlyList<WatchlistItemDto>> ListAsync(Guid userId, CancellationToken ct = default)
    {
        return await db.WatchlistItems
            .Where(w => w.UserId == userId)
            .OrderBy(w => w.AddedAt)
            .Select(w => new WatchlistItemDto(w.Ticker, w.AddedAt))
            .ToListAsync(ct);
    }

    public async Task<WatchlistItemDto> AddAsync(Guid userId, string ticker, CancellationToken ct = default)
    {
        ticker = ticker.Trim().ToUpperInvariant();
        if (string.IsNullOrEmpty(ticker) || ticker.Length > 16)
            throw new InvalidOperationException("ticker must be 1-16 characters");

        var existing = await db.WatchlistItems
            .FirstOrDefaultAsync(w => w.UserId == userId && w.Ticker == ticker, ct);
        if (existing != null) return new WatchlistItemDto(existing.Ticker, existing.AddedAt);

        var item = new WatchlistItem { UserId = userId, Ticker = ticker, AddedAt = DateTime.UtcNow };
        db.WatchlistItems.Add(item);
        await db.SaveChangesAsync(ct);

        // Best-effort: warm the natal chart cache so the daily job doesn't have to.
        try { await stockChart.GetOrCreateAsync(ticker, ct); }
        catch { /* non-fatal */ }

        return new WatchlistItemDto(item.Ticker, item.AddedAt);
    }

    public async Task<bool> RemoveAsync(Guid userId, string ticker, CancellationToken ct = default)
    {
        ticker = ticker.Trim().ToUpperInvariant();
        var item = await db.WatchlistItems
            .FirstOrDefaultAsync(w => w.UserId == userId && w.Ticker == ticker, ct);
        if (item is null) return false;
        db.WatchlistItems.Remove(item);
        await db.SaveChangesAsync(ct);
        return true;
    }
}
