using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Jyotish.Services;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Models;

namespace ShantiSangha.Trading.Services;

public class StockChartService(
    TradingDbContext db,
    IIpoChartCsvLoader csv,
    ILogger<StockChartService> logger) : IStockChartService
{
    // NYSE coordinates (40.7068, -74.0090) — fallback when CSV doesn't list the ticker.
    private const double DefaultIpoLatitude = 40.7068;
    private const double DefaultIpoLongitude = -74.0090;
    private const string DefaultIpoTimeEt = "09:30";
    private const string DefaultExchange = "UNKNOWN";

    public async Task<StockNatalChartView?> GetOrCreateAsync(string ticker, CancellationToken ct = default)
    {
        ticker = ticker.Trim().ToUpperInvariant();

        var existing = await db.StockNatalCharts.FirstOrDefaultAsync(s => s.Ticker == ticker, ct);
        if (existing != null)
        {
            return ToView(existing);
        }

        // Hydrate from CSV if we have the ticker; otherwise we can't build a chart yet —
        // return null and let the caller decide (e.g., show "no chart data" until you add a row).
        if (!csv.Rows.TryGetValue(ticker, out var seed))
        {
            logger.LogInformation("StockChartService: no IPO seed for {Ticker}; chart skipped", ticker);
            return null;
        }

        var ipoUtc = ResolveIpoUtc(seed);
        var birthTime = ParseTime(seed.FirstTradeTimeEt ?? DefaultIpoTimeEt);
        var sigs = ChartSignatures.ComputeNatalSignatures(
            birthDate: seed.IpoDate,
            birthTime: birthTime,
            latitude: seed.Latitude,
            longitude: seed.Longitude
        );

        var entity = new StockNatalChart
        {
            Ticker = seed.Ticker,
            IpoDate = seed.IpoDate,
            IpoTimeEt = seed.FirstTradeTimeEt,
            IpoLatitude = seed.Latitude,
            IpoLongitude = seed.Longitude,
            Exchange = seed.Exchange,
            SignaturesJson = JsonSerializer.Serialize(sigs),
            ComputedAt = DateTime.UtcNow,
        };

        db.StockNatalCharts.Add(entity);
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // race: another request seeded it; reload
            db.Entry(entity).State = EntityState.Detached;
            existing = await db.StockNatalCharts.FirstOrDefaultAsync(s => s.Ticker == ticker, ct);
            if (existing != null) return ToView(existing);
            throw;
        }

        return new StockNatalChartView(
            seed.Ticker,
            seed.IpoDate,
            seed.FirstTradeTimeEt,
            seed.Latitude,
            seed.Longitude,
            seed.Exchange,
            sigs,
            ipoUtc
        );
    }

    private static StockNatalChartView ToView(StockNatalChart row)
    {
        var sigs = JsonSerializer.Deserialize<List<string>>(row.SignaturesJson) ?? [];
        var ipoUtc = ResolveIpoUtc(new IpoSeedRow(
            row.Ticker, "", row.IpoDate, row.IpoTimeEt, row.Exchange, row.IpoLatitude, row.IpoLongitude));
        return new StockNatalChartView(
            row.Ticker,
            row.IpoDate,
            row.IpoTimeEt,
            row.IpoLatitude,
            row.IpoLongitude,
            row.Exchange,
            sigs,
            ipoUtc
        );
    }

    private static DateTime ResolveIpoUtc(IpoSeedRow seed)
    {
        var time = ParseTime(seed.FirstTradeTimeEt ?? DefaultIpoTimeEt);
        var ipoLocal = seed.IpoDate.ToDateTime(time);
        try
        {
            // ET = America/New_York; convert local ET → UTC
            var et = TimeZoneInfo.FindSystemTimeZoneById("America/New_York");
            return TimeZoneInfo.ConvertTimeToUtc(DateTime.SpecifyKind(ipoLocal, DateTimeKind.Unspecified), et);
        }
        catch
        {
            // crude fallback — assume EST (UTC-5); good enough for a fallback path
            return DateTime.SpecifyKind(ipoLocal.AddHours(5), DateTimeKind.Utc);
        }
    }

    private static TimeOnly ParseTime(string hhmm)
    {
        if (TimeOnly.TryParseExact(hhmm, "HH:mm", out var t)) return t;
        return new TimeOnly(9, 30);
    }
}
