using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Jobs;

/// <summary>
/// Generates a living portrait of the user — who they are through the lens of
/// their practice, their patterns, and their reflections. Cached per user,
/// regenerated when the underlying context changes meaningfully.
/// </summary>
public class GeneratePortraitJob(
    WellnessDbContext db,
    Kernel kernel,
    IPracticeQueryService practiceQuery,
    IProfileQueryService profileQuery,
    ILogger<GeneratePortraitJob> logger)
{
    public async Task RunAsync(Guid userId)
    {
        try
        {
            var today = DateOnly.FromDateTime(DateTime.UtcNow);
            var displayName = await profileQuery.GetDisplayNameAsync(userId);
            var practices = await practiceQuery.GetActivePracticesForContextAsync(userId, today);

            var recentReflections = await db.DailyReflections
                .Where(r => r.UserId == userId)
                .OrderByDescending(r => r.Date)
                .Take(10)
                .Select(r => new { r.Content, r.Date })
                .ToListAsync();

            var totalReflections = await db.DailyReflections
                .CountAsync(r => r.UserId == userId);

            var contextParts = new List<string>();

            if (displayName is not null)
                contextParts.Add($"Their name is {displayName}.");

            contextParts.Add($"They have been using the app for {totalReflections} days.");

            if (practices.Count > 0)
            {
                var practiceLines = practices.Select(p =>
                {
                    var streak = p.CurrentStreak > 0 ? $" (streak: {p.CurrentStreak} days, longest: {p.LongestStreak})" : " (no active streak)";
                    var why = !string.IsNullOrWhiteSpace(p.DeeperWhy) ? $" Why: \"{p.DeeperWhy}\"" : "";
                    return $"  - {p.Title}{streak}{why}";
                });
                contextParts.Add($"Active practices:\n{string.Join("\n", practiceLines)}");
            }

            if (recentReflections.Count > 0)
            {
                var reflLines = recentReflections.Select(r =>
                    $"  - [{r.Date:yyyy-MM-dd}] \"{r.Content}\"");
                contextParts.Add($"Recent daily reflections (to understand their arc):\n{string.Join("\n", reflLines)}");
            }

            var context = string.Join("\n\n", contextParts);

            var contextHash = ComputeHash(context);
            var existing = await db.Portraits
                .FirstOrDefaultAsync(p => p.UserId == userId);

            if (existing is not null && existing.ContextHash == contextHash)
            {
                logger.LogInformation("Portrait context unchanged for user {UserId} — skipping regeneration", userId);
                return;
            }

            var chatCompletion = kernel.GetRequiredService<IChatCompletionService>(AiModels.FastServiceId);
            var history = new ChatHistory(BuildSystemPrompt(totalReflections));

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

    private static string BuildSystemPrompt(int totalDays)
    {
        var dayContext = totalDays switch
        {
            0 => "This person just started. You know almost nothing yet. Write a seed portrait based on what they've chosen to practice. End with: 'As you practice, this portrait will grow with you.'",
            < 7 => "This person is new. You have limited data. Write what you can see so far — their chosen practices, their early patterns. Keep it grounded in what's real, not what you imagine.",
            < 30 => "You have a few weeks of data. You can start to see patterns — which practices stick, which daily reflections keep echoing, how they show up. Name what you notice.",
            _ => "You have deep history. You can see arcs, shifts, contradictions, and growth. This portrait should feel like it could only describe THIS person — specific, earned, true."
        };

        return $"""
            You write a living portrait of a person — who they are as seen through
            their spiritual practice, their patterns, and their reflections.

            This portrait appears at the top of their Journey page. It is the app
            telling them who they are, based on everything it knows. The reader
            should think: "yes, that's me" — or better, "I hadn't thought of it
            that way."

            {dayContext}

            Rules:
            - 3 to 5 sentences. No more. Every word must earn its place.
            - Write in second person ("You are..." / "You carry..." / "Your practice...")
            - Anchor in practice patterns and daily reflections — what they actually do
              and what's actually been observed about them.
            - Reference specific numbers (streak days, practice counts) naturally.
            - Name thematic threads only when they are visible in the provided
              reflections or practice history.
            - The tone is warm, observant, unhurried. Like a wise teacher who has
              been watching quietly and finally speaks.
            - Never give advice. Never instruct. Only observe and reflect back.
            - Never use exclamation marks. Never be peppy.
            - Do not use their name.
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
