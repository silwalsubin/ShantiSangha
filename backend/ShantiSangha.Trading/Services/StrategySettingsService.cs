using Microsoft.EntityFrameworkCore;
using ShantiSangha.Trading.Contracts;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public class StrategySettingsService(TradingDbContext db) : IStrategySettingsService
{
    private static readonly HashSet<string> ValidHorizons = new(StringComparer.OrdinalIgnoreCase)
    {
        "1W", "1M", "1Y",
    };

    public async Task<UserStrategySettings> GetOrCreateAsync(Guid userId, CancellationToken ct = default)
    {
        var row = await db.UserStrategySettings.FirstOrDefaultAsync(s => s.UserId == userId, ct);
        if (row is not null) return row;

        row = new UserStrategySettings { UserId = userId, UpdatedAt = DateTime.UtcNow };
        db.UserStrategySettings.Add(row);
        await db.SaveChangesAsync(ct);
        return row;
    }

    public async Task<UserStrategySettings> UpdateAsync(
        Guid userId,
        UpdateStrategySettingsRequest req,
        CancellationToken ct = default)
    {
        var row = await GetOrCreateAsync(userId, ct);

        if (req.StopLossPct is { } stop)
        {
            if (stop <= 0 || stop >= 0.5m)
                throw new InvalidOperationException("stopLossPct must be between 0 and 0.5");
            row.StopLossPct = stop;
        }
        if (req.TakeProfitPct is { } tp)
        {
            if (tp <= 0 || tp >= 1.0m)
                throw new InvalidOperationException("takeProfitPct must be between 0 and 1.0");
            row.TakeProfitPct = tp;
        }
        if (req.EntryThresholdPBuy is { } th)
        {
            if (th < 0.5m || th > 0.95m)
                throw new InvalidOperationException("entryThresholdPBuy must be between 0.50 and 0.95");
            row.EntryThresholdPBuy = th;
        }
        if (!string.IsNullOrWhiteSpace(req.EntryHorizon))
        {
            var h = req.EntryHorizon.Trim().ToUpperInvariant();
            if (!ValidHorizons.Contains(h))
                throw new InvalidOperationException("entryHorizon must be one of: 1W, 1M, 1Y");
            row.EntryHorizon = h;
        }
        if (req.CooldownDays is { } cd)
        {
            if (cd < 0 || cd > 90)
                throw new InvalidOperationException("cooldownDays must be between 0 and 90");
            row.CooldownDays = cd;
        }
        if (req.PositionCapPct is { } cap)
        {
            if (cap < 0.05m || cap > 0.5m)
                throw new InvalidOperationException("positionCapPct must be between 0.05 and 0.5");
            row.PositionCapPct = cap;
        }
        if (req.MinSectors is { } min)
        {
            if (min < 1 || min > 11)
                throw new InvalidOperationException("minSectors must be between 1 and 11");
            row.MinSectors = min;
        }
        if (req.SellSignalPSell is { } ps)
        {
            if (ps < 0.4m || ps > 0.95m)
                throw new InvalidOperationException("sellSignalPSell must be between 0.40 and 0.95");
            row.SellSignalPSell = ps;
        }

        row.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return row;
    }
}
