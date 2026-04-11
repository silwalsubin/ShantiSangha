using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Jobs;

public class GenerateDailyMantraJob(
    WellnessDbContext db,
    Kernel kernel,
    IGoalQueryService goalQuery,
    ISummaryQueryService summaryQuery,
    IInsightQueryService insightQuery,
    IProfileQueryService profileQuery,
    ILogger<GenerateDailyMantraJob> logger)
{
    public async Task RunAsync(Guid userId)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        // Already generated today?
        var exists = await db.DailyMantras.AnyAsync(m => m.UserId == userId && m.Date == today);
        if (exists) return;

        try
        {
            // Gather context about this person
            var displayName = await profileQuery.GetDisplayNameAsync(userId);
            var goals = await goalQuery.GetActiveGoalsForContextAsync(userId);
            var summaries = await summaryQuery.GetRecentSummariesAsync(userId, 3);
            var journalSummaries = await summaryQuery.GetRecentJournalSummariesAsync(userId, 3);
            var insights = await insightQuery.GetRecentInsightsAsync(userId, 3);

            // Build context summary for the AI
            var contextParts = new List<string>();

            if (displayName is not null)
                contextParts.Add($"Their name is {displayName}.");

            foreach (var g in goals)
            {
                var streak = g.CurrentStreak > 0 ? $" (current streak: {g.CurrentStreak} days)" : "";
                var why = !string.IsNullOrWhiteSpace(g.DeeperWhy) ? $" Why: \"{g.DeeperWhy}\"" : "";
                contextParts.Add($"- {g.Type} goal: {g.Title}{streak}{why}");
            }

            if (summaries.Count > 0)
                contextParts.Add($"Recent conversation themes: {string.Join("; ", summaries)}");

            if (journalSummaries.Count > 0)
                contextParts.Add($"Recent journal reflections: {string.Join("; ", journalSummaries)}");

            if (insights.Count > 0)
                contextParts.Add($"Insights from their reflections: {string.Join("; ", insights)}");

            // Check days since last visit (approximate via last mantra)
            var lastMantra = await db.DailyMantras
                .Where(m => m.UserId == userId)
                .OrderByDescending(m => m.Date)
                .FirstOrDefaultAsync();

            if (lastMantra is not null)
            {
                var daysSince = today.DayNumber - lastMantra.Date.DayNumber;
                if (daysSince > 1)
                    contextParts.Add($"They haven't opened the app in {daysSince} days.");
            }
            else
            {
                contextParts.Add("This is their first day using the app.");
            }

            var context = contextParts.Count > 0
                ? string.Join("\n", contextParts)
                : "No context available yet — they are new.";

            var chatCompletion = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory("""
                You write a single daily mantra for a spiritual wellness app called ShantiSangha.

                Rules:
                - ONE sentence. Maximum two short sentences. Never more.
                - It must feel like it was written for THIS person, TODAY. Use their context.
                - If they have a streak, acknowledge it warmly. If they've been away, welcome them back without guilt.
                - If they journaled about something heavy, speak to that gently.
                - If they're new, welcome them to the practice.
                - Tone: warm, wise, grounded. Like a caring friend who sees you clearly.
                - Never preachy. Never clinical. Never generic motivational quotes.
                - Do not use their name — speak directly, intimately.
                - Do not use quotation marks around the mantra.
                - Draw from spiritual wisdom naturally — Gita, Dhammapada, Zen — but don't quote directly.

                Bad examples (too generic):
                - "Believe in yourself today."
                - "Every day is a new beginning."
                - "You are stronger than you think."

                Good examples (personal, specific):
                - "Fourteen days of showing up. The practice is becoming you."
                - "The breath you take right now is the only one that matters."
                - "Welcome back. Nothing was lost while you were away."
                - "Yesterday you honored every commitment you made to yourself."

                Respond with ONLY the mantra. Nothing else.
                """);

            history.AddUserMessage($"Context about this person:\n{context}");

            var result = await chatCompletion.GetChatMessageContentAsync(history);
            var mantra = result.Content?.Trim().Trim('"').Trim();

            if (!string.IsNullOrWhiteSpace(mantra))
            {
                db.DailyMantras.Add(new DailyMantra
                {
                    Id = Guid.NewGuid(),
                    UserId = userId,
                    Date = today,
                    Content = mantra,
                    CreatedAt = DateTime.UtcNow
                });
                await db.SaveChangesAsync();
                logger.LogDebug("Generated daily mantra for user {UserId}: {Mantra}", userId, mantra);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate daily mantra for user {UserId}", userId);
        }
    }
}
