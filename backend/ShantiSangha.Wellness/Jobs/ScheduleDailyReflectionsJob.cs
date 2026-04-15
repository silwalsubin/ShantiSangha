using Hangfire;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;

namespace ShantiSangha.Wellness.Jobs;

/// <summary>
/// Runs hourly. For each user whose local time is currently in the early-morning
/// window (3–4am), enqueues GenerateDailyReflectionJob so their reflection is
/// ready before they open the app. Pre-generation eliminates the first-open
/// loading state when the lazy path would otherwise trigger a blocking AI call.
///
/// Only pre-generates for users who have a reflection from the past 14 days
/// (active-user heuristic). Users without a stored timezone are skipped.
/// </summary>
public class ScheduleDailyReflectionsJob(
    WellnessDbContext db,
    IProfileQueryService profileQuery,
    IBackgroundJobClient jobs,
    ILogger<ScheduleDailyReflectionsJob> logger)
{
    private const int PreGenerationHour = 3;
    private const int ActiveUserWindowDays = 14;

    public async Task RunAsync()
    {
        var now = DateTime.UtcNow;

        var profiles = await profileQuery.GetAllUserTimezonesAsync();
        if (profiles.Count == 0) return;

        // Filter to users whose local hour is in the pre-generation window.
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

        // Active-user filter: only pre-generate for users who actually use the app.
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

            // Skip if today's reflection already exists (shouldn't happen at 3am,
            // but defensive — the generation job itself also short-circuits).
            var exists = await db.DailyReflections
                .AnyAsync(r => r.UserId == userId && r.Date == localDate);
            if (exists) continue;

            jobs.Enqueue<GenerateDailyReflectionJob>(j => j.RunAsync(userId, localDate));
            enqueued++;
        }

        if (enqueued > 0)
            logger.LogInformation("Pre-generated {Count} daily reflections at {Utc} UTC", enqueued, now);
    }
}
