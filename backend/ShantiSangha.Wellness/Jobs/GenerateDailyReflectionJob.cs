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
            var milestoneThresholds = new HashSet<int> { 7, 14, 30, 60, 100, 365 };
            var milestonesHitToday = new List<string>();
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

                // A milestone was crossed today if they checked in today and their
                // streak landed on a threshold value.
                if (g.CheckedInToday == true && milestoneThresholds.Contains(g.CurrentStreak))
                {
                    milestonesHitToday.Add($"{g.Title} reached {g.CurrentStreak} days today");
                }
            }

            if (milestonesHitToday.Count > 0)
                contextParts.Add($"MILESTONE(S) HIT TODAY:\n{string.Join("\n", milestonesHitToday.Select(m => $"  - {m}"))}");

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
                - Maximum 50 words. Two to three SHORT sentences. Never more.
                - Be SPECIFIC. Reference actual data — their streaks, their journal
                  themes, their patterns. A reflection that could apply to anyone is
                  worthless.
                - ONLY speak to what they HAVE done, never what they haven't.
                  Do not mention incomplete goals, dormant commitments, or missed
                  days. If a goal has no activity, ignore it completely.
                - Never give advice or instructions. No "try to..." or "consider..."
                - Never use exclamation marks. Never be peppy.
                - Never judge, evaluate, or imply they should do more. No "while X
                  remains unfulfilled" or "yet Y continues to wait." The reflection
                  is a celebration of what IS, not a commentary on what ISN'T.
                - If they've been away, welcome them without guilt.
                - If you notice a pattern in what they DO (they always meditate after
                  journaling, their streak grew after they wrote about why), NAME it.
                - If a MILESTONE is noted in the context (a streak threshold crossed
                  today — 7, 14, 30, 60, 100, or 365 days), acknowledge it simply.
                  No gamification language. No "congrats" or "achievement." Observe
                  what this number means about them, not the number itself. Example:
                  "Thirty days of meditation. The practice has become a person, not
                  a task."
                - If there isn't enough positive data, say something honest and brief
                  about beginnings. "The first days are the quietest. But you're here."
                - Do not repeat themes from their previous reflections (provided below).
                - Tone: observant, warm, unhurried. A friend noticing something good.
                - Do not use their name.
                - Do not use quotation marks around the reflection.
                - Use simple, direct language. No flowery prose or compound sentences.

                Bad examples (judgmental, too long, or generic):
                - "Every day you show up is a victory."
                - "Your journey is uniquely yours."
                - "While your desire for self-improvement fuels repetitive acts, the
                  importance of X remains quietly unfulfilled." (NEVER write like this)
                - "Notable goals continue to lie dormant." (NEVER point out inactivity)

                Good examples (specific, brief, warm):
                - "You meditated the morning after both journal entries this week.
                  Your practice knows something you might not."
                - "Reading is the one you never skip. That says something about
                  what grounds you."
                - "You came back today without being asked. That matters more than
                  any streak."

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
