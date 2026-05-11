using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Controllers;

[ApiController]
[Authorize]
[Route("api/journal")]
public class JournalPromptController(
    WellnessDbContext db,
    ICurrentUser currentUser,
    Kernel kernel,
    IPracticeQueryService practiceQuery,
    IReflectionQueryService reflectionQuery,
    ILogger<JournalPromptController> logger) : ControllerBase
{
    /// <summary>
    /// Returns a one-sentence journal prompt personalized to the user, cached
    /// once per user per day. If no context is available (new user), returns
    /// null and the client falls back to its static prompt list.
    /// </summary>
    [HttpGet("prompt")]
    public async Task<IActionResult> GetPrompt([FromQuery] string? date, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var cached = await db.DailyJournalPrompts
            .Where(p => p.UserId == user.Id && p.Date == today)
            .Select(p => p.Content)
            .FirstOrDefaultAsync(ct);

        if (cached is not null)
            return Ok(new { Prompt = cached });

        var practices = await practiceQuery.GetActivePracticesForContextAsync(user.Id, today, ct);
        var todaysReflection = await reflectionQuery.GetRecentReflectionAsync(user.Id, ct);

        // If the user has no context at all, return null — client falls back.
        var hasContext = practices.Count > 0
            || !string.IsNullOrWhiteSpace(todaysReflection);
        if (!hasContext)
            return Ok(new { Prompt = (string?)null });

        var contextParts = new List<string>();

        foreach (var g in practices)
        {
            var streak = g.CurrentStreak > 0 ? $" ({g.CurrentStreak}-day streak)" : "";
            var why = !string.IsNullOrWhiteSpace(g.DeeperWhy) ? $" Why: \"{g.DeeperWhy}\"" : "";
            contextParts.Add($"- {g.Title}{streak}{why}");
        }

        if (!string.IsNullOrWhiteSpace(todaysReflection))
            contextParts.Add($"Today's reflection: \"{todaysReflection}\"");

        var context = string.Join("\n\n", contextParts);

        try
        {
            var chat = kernel.GetRequiredService<IChatCompletionService>(AiModels.FastServiceId);
            var history = new ChatHistory("""
                You write a single journal prompt for someone about to open a blank
                journal editor in a spiritual wellness app. The prompt appears as
                placeholder text — a door, not a demand.

                Rules:
                - ONE sentence. Under 20 words. A question or invitation.
                - Be SPECIFIC to their context — reference their actual streaks,
                  practices, or today's reflection. Generic prompts are worthless.
                - Never give advice. Never mention what they haven't done.
                - Never use exclamation marks. No emojis.
                - Tone: warm, curious, unhurried. Like a friend asking the right
                  question at the right moment.
                - Do not use their name.
                - Do not wrap the prompt in quotes.

                Bad examples:
                - "What's on your mind today?"
                - "How are you feeling?"
                - "Write about anything that comes to mind."

                Good examples:
                - "Twelve days of meditation. What has changed in how you wake up?"
                - "What would you say to the version of you from a month ago?"
                - "What is growing in you that you haven't named yet?"

                Respond with ONLY the prompt. Nothing else.
                """);
            history.AddUserMessage($"Context about this person:\n{context}");

            var result = await chat.GetChatMessageContentAsync(history, cancellationToken: ct);
            var prompt = result.Content?.Trim().Trim('"').Trim();

            if (string.IsNullOrWhiteSpace(prompt))
                return Ok(new { Prompt = (string?)null });

            db.DailyJournalPrompts.Add(new DailyJournalPrompt
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                Date = today,
                Content = prompt,
                CreatedAt = DateTime.UtcNow
            });
            await db.SaveChangesAsync(ct);

            return Ok(new { Prompt = prompt });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate journal prompt for user {UserId}", user.Id);
            return Ok(new { Prompt = (string?)null });
        }
    }
}
