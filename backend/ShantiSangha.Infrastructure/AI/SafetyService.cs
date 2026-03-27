using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Core.Models;
using ShantiSangha.Core.Services;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Infrastructure.AI;

public class SafetyService(
    IHttpClientFactory httpClientFactory,
    AppDbContext db,
    ILogger<SafetyService> logger) : ISafetyService
{
    // Phrases that trigger an immediate crisis escalation, bypassing the AI entirely
    private static readonly string[] CrisisPatterns =
    [
        "kill myself", "end my life", "want to die", "suicidal", "suicide",
        "self harm", "self-harm", "cutting myself", "hurt myself",
        "don't want to be here anymore", "no reason to live",
        "better off dead", "better off without me",
        "overdose", "take all my pills",
        "harm someone", "hurt someone", "kill someone"
    ];

    public async Task<SafetyCheckResult> CheckInputAsync(string content, CancellationToken ct = default)
    {
        // 1. Fast local crisis keyword scan — no API call needed
        var lowerContent = content.ToLowerInvariant();
        foreach (var pattern in CrisisPatterns)
        {
            if (lowerContent.Contains(pattern))
            {
                logger.LogWarning("Crisis keyword detected in user input: '{Pattern}'", pattern);
                return new SafetyCheckResult(SafetyCheckOutcome.Crisis, $"Crisis pattern: {pattern}");
            }
        }

        // 2. OpenAI moderation API for broader harmful content
        var result = await CallModerationApiAsync(content, ct);
        if (result.Outcome != SafetyCheckOutcome.Clear)
            logger.LogWarning("OpenAI moderation flagged input: {Reason}", result.Reason);

        return result;
    }

    public async Task<SafetyCheckResult> CheckOutputAsync(string content, CancellationToken ct = default)
    {
        // Scan AI response — should never contain harmful content, but verify
        var result = await CallModerationApiAsync(content, ct);
        if (result.Outcome != SafetyCheckOutcome.Clear)
            logger.LogError("OpenAI moderation flagged AI output: {Reason}", result.Reason);

        return result;
    }

    public async Task LogEventAsync(
        Guid userId,
        string eventType,
        string? triggerContent,
        string? details,
        Guid? conversationId,
        CancellationToken ct = default)
    {
        if (!Enum.TryParse<SafetyEventType>(eventType, out var parsedType))
            parsedType = SafetyEventType.ModerationFlagged;

        var safetyEvent = new SafetyEvent
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            EventType = parsedType,
            TriggerContent = triggerContent,
            Details = details,
            ConversationId = conversationId,
            CreatedAt = DateTime.UtcNow
        };

        db.SafetyEvents.Add(safetyEvent);
        await db.SaveChangesAsync(ct);
    }

    private async Task<SafetyCheckResult> CallModerationApiAsync(string content, CancellationToken ct)
    {
        try
        {
            var client = httpClientFactory.CreateClient("OpenAI");
            var response = await client.PostAsJsonAsync(
                "https://api.openai.com/v1/moderations",
                new { input = content },
                ct);

            if (!response.IsSuccessStatusCode)
            {
                logger.LogWarning("Moderation API returned {StatusCode} — allowing content through", response.StatusCode);
                return new SafetyCheckResult(SafetyCheckOutcome.Clear);
            }

            var result = await response.Content.ReadFromJsonAsync<ModerationResponse>(cancellationToken: ct);
            if (result?.Results is not { Length: > 0 })
                return new SafetyCheckResult(SafetyCheckOutcome.Clear);

            var flagged = result.Results[0];
            if (!flagged.Flagged)
                return new SafetyCheckResult(SafetyCheckOutcome.Clear);

            // Find the highest-scoring flagged category to report
            var topCategory = flagged.CategoryScores
                .OrderByDescending(kv => kv.Value)
                .First(kv => flagged.Categories.TryGetValue(kv.Key, out var isFlagged) && isFlagged);

            return new SafetyCheckResult(SafetyCheckOutcome.Flagged, $"Category: {topCategory.Key}");
        }
        catch (Exception ex)
        {
            // Never block the user because of a moderation API failure — log and continue
            logger.LogError(ex, "Moderation API call failed — allowing content through");
            return new SafetyCheckResult(SafetyCheckOutcome.Clear);
        }
    }
}

// OpenAI moderation API response shapes
file record ModerationResponse(ModerationResult[] Results);
file record ModerationResult(
    bool Flagged,
    [property: JsonPropertyName("categories")] Dictionary<string, bool> Categories,
    [property: JsonPropertyName("category_scores")] Dictionary<string, double> CategoryScores);
