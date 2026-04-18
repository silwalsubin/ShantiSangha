using Hangfire;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;

namespace ShantiSangha.Wellness.Jobs;

/// <summary>
/// Runs hourly. For each user whose local time is exactly midnight (00:xx),
/// enqueues GenerateDailyReadingJob so today's reading is ready the moment
/// they open the app. Only pre-generates for active users (reflection in
/// the past 14 days).
/// </summary>
public class ScheduleDailyReadingsJob(
    WellnessDbContext db,
    IProfileQueryService profileQuery,
    IBackgroundJobClient jobs,
    ILogger<ScheduleDailyReadingsJob> logger)
{
    private const int PreGenerationHour = 0; // midnight local
    private const int ActiveUserWindowDays = 14;

    public async Task RunAsync()
    {
        var now = DateTime.UtcNow;

        var profiles = await profileQuery.GetAllUserTimezonesAsync();
        if (profiles.Count == 0) return;

        var candidates = new List<(Guid UserId, DateOnly LocalDate)>();
        foreach (var p in profiles)
        {
            if (string.IsNullOrWhiteSpace(p.Timezone)) continue;

            TimeZoneInfo tz;
            try { tz = TimeZoneInfo.FindSystemTimeZoneById(p.Timezone); }
            catch { continue; }

            var local = TimeZoneInfo.ConvertTimeFromUtc(now, tz);
            if (local.Hour != PreGenerationHour) continue;

            candidates.Add((p.UserId, DateOnly.FromDateTime(local)));
        }

        if (candidates.Count == 0) return;

        // Active-user filter — piggybacks on reflection activity as a proxy.
        var candidateIds = candidates.Select(c => c.UserId).ToList();
        var activeCutoff = DateOnly.FromDateTime(now).AddDays(-ActiveUserWindowDays);
        var activeUsers = await db.DailyReflections
            .Where(r => candidateIds.Contains(r.UserId) && r.Date >= activeCutoff)
            .Select(r => r.UserId)
            .Distinct()
            .ToListAsync();
        var activeSet = activeUsers.ToHashSet();

        var enqueued = 0;
        foreach (var (userId, localDate) in candidates)
        {
            if (!activeSet.Contains(userId)) continue;

            var exists = await db.DailyReadings
                .AnyAsync(r => r.UserId == userId && r.Date == localDate);
            if (exists) continue;

            jobs.Enqueue<GenerateDailyReadingJob>(j => j.RunAsync(userId, localDate));
            enqueued++;
        }

        if (enqueued > 0)
            logger.LogInformation("Pre-generated {Count} daily readings at {Utc} UTC", enqueued, now);
    }
}
