using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Jobs;

/// <summary>
/// Generates a living portrait of the user — who they are through the lens of
/// their practice, their patterns, and their Vedic identity. Cached per user,
/// regenerated when the underlying context changes meaningfully.
/// </summary>
public class GeneratePortraitJob(
    WellnessDbContext db,
    Kernel kernel,
    IGoalQueryService goalQuery,
    ISummaryQueryService summaryQuery,
    IInsightQueryService insightQuery,
    IProfileQueryService profileQuery,
    IJyotishContextService jyotishService,
    ILogger<GeneratePortraitJob> logger)
{
    public async Task RunAsync(Guid userId)
    {
        try
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            var displayName = await profileQuery.GetDisplayNameAsync(userId);
            var goals = await goalQuery.GetActiveGoalsForContextAsync(userId, today);
            var summaries = await summaryQuery.GetRecentSummariesAsync(userId, 5);
            var journalSummaries = await summaryQuery.GetRecentJournalSummariesAsync(userId, 5);
            var insights = await insightQuery.GetRecentInsightsAsync(userId, 5);

            // Previous reflections — for understanding their arc
            var recentReflections = await db.DailyReflections
                .Where(r => r.UserId == userId)
                .OrderByDescending(r => r.Date)
                .Take(10)
                .Select(r => new { r.Content, r.Date })
                .ToListAsync();

            // Count total reflections (proxy for how long they've been using the app)
            var totalReflections = await db.DailyReflections
                .CountAsync(r => r.UserId == userId);

            // Vedic context
            string? birthNakshatra = null;
            string? moonRashi = null;
            try
            {
                var jyotish = await jyotishService.GetContextAsync(userId, today);
                if (jyotish is not null)
                {
                    birthNakshatra = jyotish.BirthNakshatra;
                    moonRashi = jyotish.MoonRashi;
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to load Vedic context for portrait — continuing without it");
            }

            // RAG: find thematic threads across their history
            List<string> ragEntries = [];
            try
            {
                var searchTerms = goals.Where(g => g.CurrentStreak > 0).Select(g => g.Title)
                    .Concat(journalSummaries.Take(2));
                var searchQuery = string.Join(", ", searchTerms);
                if (!string.IsNullOrWhiteSpace(searchQuery))
                {
                    var results = await insightQuery.SearchAllAsync(userId, searchQuery, 5);
                    ragEntries = results.Select(e =>
                        $"  - [{e.Type}, {e.CreatedAt:yyyy-MM-dd}] \"{e.Content}\"").ToList();
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "RAG search failed for portrait — continuing without it");
            }

            // Build context
            var contextParts = new List<string>();

            if (displayName is not null)
                contextParts.Add($"Their name is {displayName}.");

            contextParts.Add($"They have been using the app for {totalReflections} days.");

            // Vedic identity
            if (birthNakshatra is not null || moonRashi is not null)
            {
                var vedicLines = new List<string>();
                if (moonRashi is not null)
                    vedicLines.Add($"Moon rashi (Vedic moon sign): {moonRashi}");
                if (birthNakshatra is not null)
                    vedicLines.Add($"Birth nakshatra: {birthNakshatra}");
                contextParts.Add($"Vedic identity:\n{string.Join("\n", vedicLines)}");
            }

            // Goals and practice patterns
            if (goals.Count > 0)
            {
                var goalLines = goals.Select(g =>
                {
                    var streak = g.CurrentStreak > 0 ? $" (streak: {g.CurrentStreak} days, longest: {g.LongestStreak})" : " (no active streak)";
                    var why = !string.IsNullOrWhiteSpace(g.DeeperWhy) ? $" Why: \"{g.DeeperWhy}\"" : "";
                    return $"  - {g.Type}: {g.Title}{streak}{why}";
                });
                contextParts.Add($"Active practices and goals:\n{string.Join("\n", goalLines)}");
            }

            // Conversation themes
            if (summaries.Count > 0)
                contextParts.Add($"Recurring conversation themes:\n{string.Join("\n", summaries.Select(s => $"  - {s}"))}");

            // Journal themes
            if (journalSummaries.Count > 0)
                contextParts.Add($"Journal themes:\n{string.Join("\n", journalSummaries.Select(s => $"  - {s}"))}");

            // Insights (patterns the AI has noticed)
            if (insights.Count > 0)
                contextParts.Add($"Patterns noticed over time:\n{string.Join("\n", insights.Select(i => $"  - {i}"))}");

            // RAG entries
            if (ragEntries.Count > 0)
                contextParts.Add($"Thematic threads from their history:\n{string.Join("\n", ragEntries)}");

            // Recent reflections for arc
            if (recentReflections.Count > 0)
            {
                var reflLines = recentReflections.Select(r =>
                    $"  - [{r.Date:yyyy-MM-dd}] \"{r.Content}\"");
                contextParts.Add($"Recent daily reflections (to understand their arc):\n{string.Join("\n", reflLines)}");
            }

            var context = string.Join("\n\n", contextParts);

            // Check if context has changed since last portrait
            var contextHash = ComputeHash(context);
            var existing = await db.Portraits
                .FirstOrDefaultAsync(p => p.UserId == userId);

            if (existing is not null && existing.ContextHash == contextHash)
            {
                logger.LogInformation("Portrait context unchanged for user {UserId} — skipping regeneration", userId);
                return;
            }

            // Generate portrait
            var chatCompletion = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory(BuildSystemPrompt(totalReflections, birthNakshatra is not null));

            history.AddUserMessage($"Everything known about this person:\n{context}");

            var result = await chatCompletion.GetChatMessageContentAsync(history);
            var portrait = result.Content?.Trim().Trim('"').Trim();

            if (!string.IsNullOrWhiteSpace(portrait))
            {
                if (existing is not null)
                {
                    existing.Content = portrait;
                    existing.ContextHash = contextHash;
                    existing.CreatedAt = DateTime.UtcNow;
                }
                else
                {
                    db.Portraits.Add(new Portrait
                    {
                        Id = Guid.NewGuid(),
                        UserId = userId,
                        Content = portrait,
                        ContextHash = contextHash,
                        CreatedAt = DateTime.UtcNow
                    });
                }

                await db.SaveChangesAsync();
                logger.LogInformation("Generated portrait for user {UserId}", userId);
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate portrait for user {UserId}", userId);
        }
    }

    private static string BuildSystemPrompt(int totalDays, bool hasVedicIdentity)
    {
        var dayContext = totalDays switch
        {
            0 => "This person just started. You know almost nothing yet. Write a seed portrait based on their nakshatra qualities and what they've chosen to practice. End with: 'As you practice, this portrait will grow with you.'",
            < 7 => "This person is new. You have limited data. Write what you can see so far — their chosen practices, their early patterns. Keep it grounded in what's real, not what you imagine.",
            < 30 => "You have a few weeks of data. You can start to see patterns — which practices stick, what themes emerge in their journals, how they show up. Name what you notice.",
            _ => "You have deep history. You can see arcs, shifts, contradictions, and growth. This portrait should feel like it could only describe THIS person — specific, earned, true."
        };

        return $"""
            You write a living portrait of a person — who they are as seen through
            their spiritual practice, their patterns, and their Vedic identity.

            This portrait appears at the top of their Journey page. It is not a
            horoscope. It is not a personality test result. It is the app telling
            them who they are, based on everything it knows. The reader should
            think: "yes, that's me" — or better, "I hadn't thought of it that way."

            {dayContext}

            Rules:
            - 3 to 5 sentences. No more. Every word must earn its place.
            - Write in second person ("You are..." / "You carry..." / "Your practice...")
            - Blend Vedic identity with practice data seamlessly. Not "Your nakshatra
              is Mrigashirsha and also you meditate." Instead: "You carry the seeker's
              restlessness of Mrigashirsha — and your 47-day meditation streak suggests
              you've learned to make that restlessness sit still."
            - If Vedic identity is available, let it anchor the portrait. The nakshatra
              quality should feel like the foundation of who they are, with practice
              data as evidence.
            - If no Vedic identity, anchor in practice patterns and journal themes.
            - Reference specific numbers (streak days, practice counts) naturally.
            - Name thematic threads from their journals/conversations if available.
              "Patience keeps appearing in your words" or "You circle back to the
              question of discipline — not whether you have it, but what it means."
            - The tone is warm, observant, unhurried. Like a wise teacher who has
              been watching quietly and finally speaks.
            - Never give advice. Never instruct. Only observe and reflect back.
            - Never use exclamation marks. Never be peppy.
            - Do not use their name.
            - Do not label anything as "Vedic astrology" or "according to your chart."
              Speak with that knowledge naturally, as if you simply know.
            - The portrait should make them feel SEEN — known in a way that no other
              app or tool could replicate. This is the sunk cost made visible.

            Respond with ONLY the portrait. Nothing else.
            """;
    }

    private static string ComputeHash(string input)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(input));
        return Convert.ToHexString(bytes)[..16];
    }
}
