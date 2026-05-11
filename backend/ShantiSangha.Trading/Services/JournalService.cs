using Microsoft.EntityFrameworkCore;
using ShantiSangha.Trading.Contracts;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public class JournalService(TradingDbContext db) : IJournalService
{
    public async Task<IReadOnlyList<JournalEntryDto>> ListAsync(
        Guid userId, int limit = 50, CancellationToken ct = default)
    {
        limit = Math.Clamp(limit, 1, 200);
        var rows = await db.TradeJournalEntries
            .Where(j => j.UserId == userId)
            .OrderByDescending(j => j.CreatedAt)
            .Take(limit)
            .ToListAsync(ct);
        return rows.Select(ToDto).ToList();
    }

    public async Task<JournalEntryDto> CreateAsync(
        Guid userId, CreateJournalEntryRequest req, CancellationToken ct = default)
    {
        var ticker = (req.Ticker ?? string.Empty).Trim().ToUpperInvariant();
        if (string.IsNullOrEmpty(ticker) || ticker.Length > 16)
            throw new InvalidOperationException("ticker must be 1-16 characters");
        if (!Enum.TryParse<TradeJournalKind>(req.Kind, ignoreCase: true, out var kind))
            throw new InvalidOperationException("kind must be one of: Entry, Exit, Trim, AddOn, Note");
        if (req.Reason is { Length: > 500 })
            throw new InvalidOperationException("reason must be <= 500 characters");

        var row = new TradeJournalEntry
        {
            UserId = userId,
            Ticker = ticker,
            Kind = kind,
            Price = req.Price,
            Shares = req.Shares,
            Reason = string.IsNullOrWhiteSpace(req.Reason) ? null : req.Reason.Trim(),
            CreatedAt = DateTime.UtcNow,
        };
        db.TradeJournalEntries.Add(row);
        await db.SaveChangesAsync(ct);
        return ToDto(row);
    }

    public async Task<bool> DeleteAsync(Guid userId, Guid id, CancellationToken ct = default)
    {
        var row = await db.TradeJournalEntries
            .FirstOrDefaultAsync(j => j.UserId == userId && j.Id == id, ct);
        if (row is null) return false;
        db.TradeJournalEntries.Remove(row);
        await db.SaveChangesAsync(ct);
        return true;
    }

    private static JournalEntryDto ToDto(TradeJournalEntry j) =>
        new(j.Id, j.Ticker, j.Kind.ToString(), j.Price, j.Shares, j.Reason, j.CreatedAt);
}
