using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Jobs;

public class GenerateDailyReflectionJob(
    WellnessDbContext db,
    Kernel kernel,
    IGoalQueryService goalQuery,
    ISummaryQueryService summaryQuery,
    IInsightQueryService insightQuery,
    IProfileQueryService profileQuery,
    IPushNotificationService pushService,
    ILogger<GenerateDailyReflectionJob> logger)
{
    public async Task RunAsync(Guid userId, DateOnly? localDate = null)
    {
        var today = localDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        var exists = await db.DailyReflections.AnyAsync(r => r.UserId == userId && r.Date == today);
        if (exists) return;

        try
        {
            var displayName = await profileQuery.GetDisplayNameAsync(userId);
            var goals = await goalQuery.GetActiveGoalsForContextAsync(userId, today);
            var summaries = await summaryQuery.GetRecentSummariesAsync(userId, 5);
            var journalSummaries = await summaryQuery.GetRecentJournalSummariesAsync(userId, 5);
            var insights = await insightQuery.GetRecentInsightsAsync(userId, 5);

            // Get previous reflections to avoid repetition
            var previousReflections = await db.DailyReflections
                .Where(r => r.UserId == userId)
                .OrderByDescending(r => r.Date)
                .Take(3)
                .Select(r => r.Content)
                .ToListAsync();

            // Build rich context
            var contextParts = new List<string>();

            if (displayName is not null)
                contextParts.Add($"Their name is {displayName}.");

            // Goals with pattern data
            foreach (var g in goals)
            {
                var streak = g.CurrentStreak > 0 ? $" (current streak: {g.CurrentStreak} days, longest: {g.LongestStreak})" : " (no active streak)";
                var why = !string.IsNullOrWhiteSpace(g.DeeperWhy) ? $" Their deeper why: \"{g.DeeperWhy}\"" : "";
                var checkedIn = g.CheckedInToday switch
                {
                    true => " — completed today",
                    false => " — not yet done today",
                    _ => ""
                };
                contextParts.Add($"- {g.Type} goal: {g.Title}{streak}{checkedIn}{why}");
            }

            if (summaries.Count > 0)
                contextParts.Add($"Recent conversation themes:\n{string.Join("\n", summaries.Select(s => $"  - {s}"))}");

            if (journalSummaries.Count > 0)
                contextParts.Add($"Recent journal reflections:\n{string.Join("\n", journalSummaries.Select(s => $"  - {s}"))}");

            if (insights.Count > 0)
                contextParts.Add($"Patterns from their reflections:\n{string.Join("\n", insights.Select(i => $"  - {i}"))}");

            // Check days since last visit
            var lastReflection = await db.DailyReflections
                .Where(r => r.UserId == userId)
                .OrderByDescending(r => r.Date)
                .FirstOrDefaultAsync();

            if (lastReflection is not null)
            {
                var daysSince = today.DayNumber - lastReflection.Date.DayNumber;
                if (daysSince > 1)
                    contextParts.Add($"They haven't opened the app in {daysSince} days.");
            }
            else
            {
                // Check if they have a mantra history as proxy for app usage
                var lastMantra = await db.DailyMantras
                    .Where(m => m.UserId == userId)
                    .OrderByDescending(m => m.Date)
                    .FirstOrDefaultAsync();

                if (lastMantra is null)
                    contextParts.Add("This is their first day using the app.");
            }

            if (previousReflections.Count > 0)
                contextParts.Add($"Previous reflections (DO NOT repeat these themes):\n{string.Join("\n", previousReflections.Select(r => $"  - \"{r}\""))}");

            var context = contextParts.Count > 0
                ? string.Join("\n\n", contextParts)
                : "No context available yet — they are new.";

            var chatCompletion = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory("""
                You write a single daily reflection for a person using a spiritual
                wellness app. This reflection appears when they open the app — it is
                the first meaningful thing they read.

                Your job is to NOTICE something. Not to advise. Not to motivate.
                Not to teach. To observe something about their patterns, their
                practice, their journey that they might not have seen themselves.

                Rules:
                - 2 to 4 sentences. Never more. Brevity is respect.
                - Be SPECIFIC. Reference actual data — their streaks, their journal
                  themes, their patterns. A reflection that could apply to anyone is
                  worthless.
                - Never give advice or instructions. No "try to..." or "consider..."
                - Never use exclamation marks. Never be peppy.
                - Never shame what was missed. Only observe what is.
                - If they've been away, welcome them without guilt.
                - If you notice a pattern (they always skip on weekends, they journal
                  after hard days, their streak grew after they wrote about why), NAME
                  it. That's the surprise.
                - If there isn't enough data to say something specific, say something
                  honest about beginnings. "The first days are the quietest. The
                  practice hasn't found its rhythm yet — but you're here."
                - Do not repeat themes from their previous reflections (provided below).
                - Tone: observant, warm, unhurried. Like a friend who has been quietly
                  watching and finally says the thing you needed to hear.
                - Do not use their name.
                - Do not use quotation marks around the reflection.

                Bad examples (too generic):
                - "Every day you show up is a victory."
                - "Your journey is uniquely yours."
                - "Keep going, you're doing great."

                Good examples (specific, observant):
                - "You journaled about your father twice this week. Both times, you
                  meditated the next morning. You may not see the pattern, but your
                  practice does."
                - "Reading is the one practice you never skip. Even on the days
                  everything else falls away, you open a book. That says something
                  about what grounds you."
                - "Your longest streak ended four days ago. You came back today without
                  needing to be asked. That matters more than the streak did."
                - "Three weeks ago you said meditation was about being present for your
                  kids. Fourteen days in, something shifted in your journals — you
                  stopped writing about stress and started writing about mornings."

                Respond with ONLY the reflection. Nothing else.
                """);

            history.AddUserMessage($"Context about this person:\n{context}");

            var result = await chatCompletion.GetChatMessageContentAsync(history);
            var reflection = result.Content?.Trim().Trim('"').Trim();

            if (!string.IsNullOrWhiteSpace(reflection))
            {
                db.DailyReflections.Add(new DailyReflection
                {
                    Id = Guid.NewGuid(),
                    UserId = userId,
                    Date = today,
                    Content = reflection,
                    CreatedAt = DateTime.UtcNow
                });
                await db.SaveChangesAsync();
                logger.LogInformation("Generated daily reflection for user {UserId}", userId);

                await pushService.SendSilentPushAsync(userId, new Dictionary<string, string> { ["type"] = "reflection" });
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate daily reflection for user {UserId}", userId);
        }
    }
}
