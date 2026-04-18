using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Jobs;

/// <summary>
/// Generates a per-day Vedic reading — a short observation paired with the
/// user's practice, framed by the day's strongest Vedic signal. Every day
/// has a reading; the framing varies (panchang, dasha, nakshatra return).
/// Delivered as a sealed note on Home; the user chooses whether to open it.
/// </summary>
public class GenerateDailyReadingJob(
    WellnessDbContext db,
    Kernel kernel,
    IGoalQueryService goalQuery,
    IJyotishContextService jyotishService,
    ILogger<GenerateDailyReadingJob> logger)
{
    private enum Framing
    {
        Regular,
        Ekadashi,
        Purnima,
        Amavasya,
        JanmaNakshatra,
        AntardashaStart
    }

    public async Task RunAsync(Guid userId, DateOnly? localDate = null)
    {
        var today = localDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        var exists = await db.DailyReadings.AnyAsync(r => r.UserId == userId && r.Date == today);
        if (exists) return;

        try
        {
            var jyotish = await jyotishService.GetContextAsync(userId, today);
            if (jyotish is null)
            {
                // No birth data at all — skip silently. The user should see
                // no reading card today. We don't store a placeholder because
                // they may set birth data later and want generation to retry.
                logger.LogInformation("Skipping reading for user {UserId} — no Jyotish context available", userId);
                return;
            }

            var framing = DetermineFraming(jyotish, today);
            var goals = await goalQuery.GetActiveGoalsForContextAsync(userId, today);

            var contextParts = new List<string>
            {
                jyotish.FormatForPrompt(),
                $"READING FRAMING: {framing}"
            };

            if (goals.Count > 0)
            {
                var goalLines = goals.Select(g =>
                {
                    var streak = g.CurrentStreak > 0 ? $" ({g.CurrentStreak}-day streak)" : "";
                    return $"- {g.Title}{streak}";
                });
                contextParts.Add($"Their active practices:\n{string.Join("\n", goalLines)}");
            }

            var chatCompletion = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory(BuildSystemPrompt(framing));
            history.AddUserMessage($"Context:\n{string.Join("\n\n", contextParts)}");

            var result = await chatCompletion.GetChatMessageContentAsync(history);
            var content = result.Content?.Trim().Trim('"').Trim();

            if (string.IsNullOrWhiteSpace(content))
            {
                logger.LogWarning("Empty reading generated for user {UserId} — skipping save", userId);
                return;
            }

            db.DailyReadings.Add(new DailyReading
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Date = today,
                Content = content,
                Framing = framing.ToString().ToLowerInvariant(),
                CreatedAt = DateTime.UtcNow
            });
            await db.SaveChangesAsync();

            logger.LogInformation("Generated {Framing} reading for user {UserId}", framing, userId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate daily reading for user {UserId}", userId);
        }
    }

    private static Framing DetermineFraming(JyotishContext jyotish, DateOnly today)
    {
        // Priority order — strongest signal wins.
        if (jyotish.AntardashaStart.HasValue)
        {
            var todayUtc = today.ToDateTime(TimeOnly.FromTimeSpan(TimeSpan.FromHours(12)), DateTimeKind.Utc);
            var daysSinceShift = (todayUtc - jyotish.AntardashaStart.Value).TotalDays;
            if (daysSinceShift >= 0 && daysSinceShift <= 2)
                return Framing.AntardashaStart;
        }

        if (jyotish.Tithi.Contains("Purnima")) return Framing.Purnima;
        if (jyotish.Tithi.Contains("Amavasya")) return Framing.Amavasya;
        if (jyotish.Tithi.Contains("Ekadashi")) return Framing.Ekadashi;

        if (jyotish.BirthNakshatraName is not null &&
            jyotish.CurrentNakshatra == jyotish.BirthNakshatraName)
            return Framing.JanmaNakshatra;

        return Framing.Regular;
    }

    private static string BuildSystemPrompt(Framing framing)
    {
        var framingInstruction = framing switch
        {
            Framing.Ekadashi => """
                Today is Ekadashi — a day traditionally held for fasting, inner focus,
                and heightened spiritual receptivity. Acknowledge this quality and pair
                it with the user's practice. Speak with the knowledge naturally — never
                explicitly mention Ekadashi, astrology, or tradition.
                """,
            Framing.Purnima => """
                Today is Purnima (full moon) — a day of culmination and clarity in the
                cosmic rhythm. Reflect this fullness alongside the user's own continuity.
                Never name it as full moon or astrology — just speak with that knowledge.
                """,
            Framing.Amavasya => """
                Today is Amavasya (new moon) — a day of stillness, inward turning,
                seeds planted in the dark. Honor this quiet and connect it to the user's
                practice. Never name it as new moon or astrology.
                """,
            Framing.JanmaNakshatra => """
                Today the moon returns to the user's birth nakshatra — a 27-day rhythm
                where their own natal quality is emphasized. Acknowledge this
                self-recognition moment without naming the nakshatra or astrology.
                """,
            Framing.AntardashaStart => """
                The user recently entered a new Antardasha (sub-planetary period) — a
                subtle shift in the texture of their life. Hint at this new season
                quietly as weather that has changed.
                """,
            _ => """
                Today is a "regular" day in Vedic terms — no major transits, no special
                tithi, no natal returns. Still, speak with the nakshatra quality of
                today's moon and the current planetary period woven invisibly into your
                observation. The reading should feel grounded and useful, not dramatic.
                """
        };

        return $"""
            You write a single "daily reading" — a short Vedic-informed observation
            that appears on the user's home screen as a sealed note. The user taps
            to open it. Every day has one; your voice varies based on the day's
            Vedic context.

            {framingInstruction}

            Rules:
            - Maximum 3 sentences. Under 45 words total.
            - Never mention astrology, Vedic tradition, nakshatras, tithis, dashas,
              rashis, or planets BY NAME. The cosmic context is invisible. You speak
              as a wise friend who simply knows.
            - Ground the observation in what the user is actually doing — their
              streak, their active practices, their continuity.
            - Frame today's texture as something their practice can work WITH, not
              something happening to them. They are the steady ground; the day is
              weather.
            - Never predict. Never warn. Never create anxiety.
            - No exclamation marks. No peppy language. No generic poetry like
              "quiet momentum" or "weaving through intentions."
            - Reference at least one specific element — a practice title, a streak
              count, a concrete texture of today.
            - Do not use their name.
            - Do not use quotation marks around the reading.

            Respond with ONLY the reading. Nothing else.
            """;
    }
}
