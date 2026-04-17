using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
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
    IGoalQueryService goalQuery,
    IReflectionQueryService reflectionQuery,
    ISummaryQueryService summaryQuery,
    IInsightQueryService insightQuery,
    IJyotishContextService jyotishService,
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

        // Gather context
        var goals = await goalQuery.GetActiveGoalsForContextAsync(user.Id, today, ct);
        var todaysReflection = await reflectionQuery.GetRecentReflectionAsync(user.Id, ct);
        var journalSummaries = await summaryQuery.GetRecentJournalSummariesAsync(user.Id, 3, ct);
        var conversationSummaries = await summaryQuery.GetRecentSummariesAsync(user.Id, 3, ct);
        var insights = await insightQuery.GetRecentInsightsAsync(user.Id, 3, ct);

        // RAG: search for thematically relevant AND distant entries
        IReadOnlyList<ShantiSangha.Shared.Models.SemanticSearchResultDto> relatedEntries = [];
        IReadOnlyList<ShantiSangha.Shared.Models.SemanticSearchResultDto> unexploredEntries = [];
        try
        {
            // Find what's semantically close to recent themes (for callbacks)
            var recentTheme = journalSummaries.FirstOrDefault() ?? conversationSummaries.FirstOrDefault();
            if (recentTheme is not null)
            {
                relatedEntries = await insightQuery.SearchAllAsync(user.Id, recentTheme, 3, ct);
            }
        }
        catch { /* RAG is optional enrichment */ }

        // If the user has no context at all, return null — client falls back.
        var hasContext = goals.Count > 0
            || !string.IsNullOrWhiteSpace(todaysReflection)
            || journalSummaries.Count > 0
            || conversationSummaries.Count > 0
            || insights.Count > 0;
        if (!hasContext)
            return Ok(new { Prompt = (string?)null });

        var contextParts = new List<string>();

        foreach (var g in goals)
        {
            var streak = g.CurrentStreak > 0 ? $" ({g.CurrentStreak}-day streak)" : "";
            var why = !string.IsNullOrWhiteSpace(g.DeeperWhy) ? $" Why: \"{g.DeeperWhy}\"" : "";
            contextParts.Add($"- {g.Title}{streak}{why}");
        }

        if (!string.IsNullOrWhiteSpace(todaysReflection))
            contextParts.Add($"Today's reflection: \"{todaysReflection}\"");

        if (journalSummaries.Count > 0)
            contextParts.Add($"Recent journal themes:\n{string.Join("\n", journalSummaries.Select(s => $"  - {s}"))}");

        if (conversationSummaries.Count > 0)
            contextParts.Add($"Recent conversation themes:\n{string.Join("\n", conversationSummaries.Select(s => $"  - {s}"))}");

        if (insights.Count > 0)
            contextParts.Add($"Saved insights:\n{string.Join("\n", insights.Select(i => $"  - {i}"))}");

        // Jyotish: today's moon nakshatra quality — invisible thematic influence
        try
        {
            var jyotish = await jyotishService.GetContextAsync(user.Id, today, ct);
            if (jyotish is not null)
            {
                contextParts.Add($"""
                    Today's invisible quality (from the moon's position — NEVER name it
                    as astrology, just let it shape the question you ask):
                    The quality of today is "{jyotish.CurrentNakshatra}" — associated with
                    {GetNakshatraPromptHint(jyotish.CurrentNakshatra)}.
                    Let this quality influence the direction of your prompt. If the quality
                    is "storms that clear the way," ask about what needed to break. If it's
                    "growth and creativity," ask about what is forming. The user should feel
                    the resonance without knowing its source.
                    """);
            }
        }
        catch { /* Jyotish is optional enrichment */ }

        // RAG-sourced thematic connections
        if (relatedEntries.Count > 0)
        {
            var lines = relatedEntries.Select(e =>
                $"  - [{e.Type}, {e.CreatedAt:yyyy-MM-dd}] \"{e.Content}\"");
            contextParts.Add($"Past entries related to recent themes (for callbacks):\n{string.Join("\n", lines)}");
        }

        var context = string.Join("\n\n", contextParts);

        try
        {
            var chat = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory("""
                You write a single journal prompt for someone about to open a blank
                journal editor in a spiritual wellness app. The prompt appears as
                placeholder text — a door, not a demand.

                Rules:
                - ONE sentence. Under 20 words. A question or invitation.
                - Be SPECIFIC to their context — reference their actual streaks,
                  journal themes, or reflections. Generic prompts are worthless.
                - Never give advice. Never mention what they haven't done.
                - Never use exclamation marks. No emojis.
                - Tone: warm, curious, unhurried. Like a friend asking the right
                  question at the right moment.
                - If past entries are provided, use them for CALLBACKS — reference
                  something from days or weeks ago and invite the user to revisit
                  it. "You wrote about patience two weeks ago. Where is that now?"
                  This creates the feeling that the app remembers their story.
                - Do not use their name.
                - Do not wrap the prompt in quotes.

                Bad examples:
                - "What's on your mind today?"
                - "How are you feeling?"
                - "Write about anything that comes to mind."

                - If an "invisible quality" is provided, let it SHAPE your question.
                  Don't name it. Don't explain it. Just let it tilt the direction.
                  If the quality is about "storms that clear," ask about release.
                  If it's about "roots," ask about foundation. The user won't know
                  why the prompt feels right. That's the point.

                Good examples:
                - "Twelve days of meditation. What has changed in how you wake up?"
                - "You wrote about feeling stuck last week. Where is that now?"
                - "What would you say to the version of you from a month ago?"
                - "The word 'tired' came up twice this week. What's underneath it?"
                - "What needed to fall away before you could see clearly?" (Ardra day)
                - "What is growing in you that you haven't named yet?" (Rohini day)

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

    /// <summary>
    /// Maps nakshatra names to prompt-worthy emotional/thematic hints.
    /// These hints guide the AI without naming astrology.
    /// </summary>
    private static string GetNakshatraPromptHint(string nakshatra) => nakshatra switch
    {
        "Ashwini" => "fresh starts, courage, the energy of beginning something new",
        "Bharani" => "transformation, endurance, carrying something heavy toward birth",
        "Krittika" => "fire, purification, cutting away what doesn't serve",
        "Rohini" => "growth, creativity, something tender taking root",
        "Mrigashirsha" => "seeking, curiosity, following a thread you can't quite name",
        "Ardra" => "storms that clear the way, necessary destruction, tears that heal",
        "Punarvasu" => "return, renewal, coming back to something you left behind",
        "Pushya" => "nourishment, devotion, being held by something larger",
        "Ashlesha" => "intensity, depth, what lives beneath the surface",
        "Magha" => "ancestry, authority, the weight and gift of where you come from",
        "Purva Phalguni" => "rest, enjoyment, permission to receive",
        "Uttara Phalguni" => "service, discernment, giving from fullness",
        "Hasta" => "skill, craftsmanship, the intelligence of your hands",
        "Chitra" => "brilliance, independence, creating something only you can make",
        "Swati" => "flexibility, movement, being unattached enough to bend",
        "Vishakha" => "determination, single-pointed purpose, the final stretch",
        "Anuradha" => "devotion, friendship, loyalty to what matters",
        "Jyeshtha" => "seniority, protection, the responsibility of knowing more",
        "Mula" => "roots, foundation, digging down to what is true",
        "Purva Ashadha" => "invincibility, courage before the battle, declaring what you stand for",
        "Uttara Ashadha" => "unwavering commitment, the strength that comes after doubt",
        "Shravana" => "listening, learning, hearing what has always been said",
        "Dhanishta" => "rhythm, abundance, the music beneath discipline",
        "Shatabhisha" => "healing, solitude, the medicine of being alone with truth",
        "Purva Bhadrapada" => "fiery transformation, burning away the old self",
        "Uttara Bhadrapada" => "depth, stability, the calm after the fire",
        "Revati" => "completion, transcendence, the journey arriving at its destination",
        _ => "presence and awareness"
    };
}
