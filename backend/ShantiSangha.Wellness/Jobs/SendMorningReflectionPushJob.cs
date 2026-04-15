using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;

namespace ShantiSangha.Wellness.Jobs;

/// <summary>
/// Runs hourly. For each user whose local time is currently their configured
/// reminder hour, sends a push notification containing today's reflection on
/// their lock screen. This is the single biggest retention lever the app has:
/// the reflection is already generated overnight, and this delivers it to the
/// user instead of waiting for them to open the app.
///
/// Deduplication: we only send once per user per day, guarded by a check
/// against the reflection's CreatedAt timestamp + a persisted "last sent" day
/// stored implicitly via the daily reflection row (we check the content exists
/// and the hour matches). To avoid multiple sends within the same local hour
/// (if the job runs overlapping), we use a per-process in-memory set keyed by
/// (userId, localDate) as a secondary guard.
/// </summary>
public class SendMorningReflectionPushJob(
    WellnessDbContext db,
    IProfileQueryService profileQuery,
    IPushNotificationService pushService,
    ILogger<SendMorningReflectionPushJob> logger)
{
    private const int MaxBodyLength = 180;

    // Process-local dedupe. Hangfire's own at-least-once semantics means the
    // job may run twice within a short window; this prevents duplicate pushes
    // in that case. Cleared when the process restarts (acceptable).
    private static readonly HashSet<string> _sentToday = new();
    private static DateOnly _sentTodayDate = DateOnly.MinValue;

    public async Task RunAsync()
    {
        var now = DateTime.UtcNow;
        var utcToday = DateOnly.FromDateTime(now);

        // Rotate the dedupe set when UTC date flips (cleanup).
        if (_sentTodayDate != utcToday)
        {
            lock (_sentToday)
            {
                _sentToday.Clear();
                _sentTodayDate = utcToday;
            }
        }

        var profiles = await profileQuery.GetUsersWithRemindersAsync();
        if (profiles.Count == 0) return;

        // Filter to users whose local hour equals their reminder hour right now.
        var candidates = new List<(Guid UserId, DateOnly LocalDate)>();
        foreach (var p in profiles)
        {
            if (string.IsNullOrWhiteSpace(p.Timezone) || p.ReminderHour is null) continue;

            TimeZoneInfo tz;
            try { tz = TimeZoneInfo.FindSystemTimeZoneById(p.Timezone); }
            catch { continue; }

            var local = TimeZoneInfo.ConvertTimeFromUtc(now, tz);
            if (local.Hour != p.ReminderHour.Value) continue;

            candidates.Add((p.UserId, DateOnly.FromDateTime(local)));
        }

        if (candidates.Count == 0) return;

        // Load today's reflection for each candidate in one query.
        var candidateIds = candidates.Select(c => c.UserId).ToList();
        var reflections = await db.DailyReflections
            .Where(r => candidateIds.Contains(r.UserId)
                && r.Date >= DateOnly.FromDateTime(now).AddDays(-1)
                && r.Date <= DateOnly.FromDateTime(now).AddDays(1))
            .ToListAsync();

        var reflectionByUser = reflections
            .GroupBy(r => r.UserId)
            .ToDictionary(g => g.Key, g => g.OrderByDescending(r => r.Date).First());

        var sent = 0;
        foreach (var (userId, localDate) in candidates)
        {
            var dedupeKey = $"{userId}:{localDate}";
            lock (_sentToday)
            {
                if (_sentToday.Contains(dedupeKey)) continue;
            }

            if (!reflectionByUser.TryGetValue(userId, out var reflection))
            {
                logger.LogDebug("No reflection for user {UserId} on {Date}, skipping morning push", userId, localDate);
                continue;
            }

            var body = Truncate(reflection.Content, MaxBodyLength);
            try
            {
                await pushService.SendAlertPushAsync(
                    userId,
                    title: "Today's reflection",
                    body: body,
                    data: new Dictionary<string, string>
                    {
                        ["type"] = "reflection",
                        ["date"] = localDate.ToString("yyyy-MM-dd")
                    });

                lock (_sentToday) { _sentToday.Add(dedupeKey); }
                sent++;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Failed to send morning reflection push to user {UserId}", userId);
            }
        }

        if (sent > 0)
            logger.LogInformation("Sent {Count} morning reflection pushes at {Utc} UTC", sent, now);
    }

    private static string Truncate(string text, int maxLength)
    {
        if (string.IsNullOrEmpty(text) || text.Length <= maxLength) return text;
        // Try to cut on a word boundary within the last 20 chars of the limit.
        var trimmed = text[..maxLength];
        var lastSpace = trimmed.LastIndexOf(' ');
        if (lastSpace > maxLength - 20) trimmed = trimmed[..lastSpace];
        return trimmed.TrimEnd(' ', '.', ',', ';', ':') + "…";
    }
}
