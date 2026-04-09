using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Chat.Safety;

public class SafetyService(
    IHttpClientFactory httpClientFactory,
    IEventBus eventBus,
    ILogger<SafetyService> logger) : ISafetyService
{
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
        var lowerContent = content.ToLowerInvariant();
        foreach (var pattern in CrisisPatterns)
        {
            if (lowerContent.Contains(pattern))
            {
                logger.LogWarning("Crisis keyword detected in user input: '{Pattern}'", pattern);
                return new SafetyCheckResult(SafetyCheckOutcome.Crisis, $"Crisis pattern: {pattern}");
            }
        }

        var result = await CallModerationApiAsync(content, ct);
        if (result.Outcome != SafetyCheckOutcome.Clear)
            logger.LogWarning("OpenAI moderation flagged input: {Reason}", result.Reason);

        return result;
    }

    public async Task<SafetyCheckResult> CheckOutputAsync(string content, CancellationToken ct = default)
    {
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
        await eventBus.PublishAsync(new SafetyEventOccurredEvent(
            userId, eventType, triggerContent, details, conversationId), ct);
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
                logger.LogWarning("Moderation API returned {StatusCode} -- allowing content through", response.StatusCode);
                return new SafetyCheckResult(SafetyCheckOutcome.Clear);
            }

            var result = await response.Content.ReadFromJsonAsync<ModerationResponse>(cancellationToken: ct);
            if (result?.Results is not { Length: > 0 })
                return new SafetyCheckResult(SafetyCheckOutcome.Clear);

            var flagged = result.Results[0];
            if (!flagged.Flagged)
                return new SafetyCheckResult(SafetyCheckOutcome.Clear);

            var topCategory = flagged.CategoryScores
                .OrderByDescending(kv => kv.Value)
                .First(kv => flagged.Categories.TryGetValue(kv.Key, out var isFlagged) && isFlagged);

            return new SafetyCheckResult(SafetyCheckOutcome.Flagged, $"Category: {topCategory.Key}");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Moderation API call failed -- allowing content through");
            return new SafetyCheckResult(SafetyCheckOutcome.Clear);
        }
    }
}

file record ModerationResponse(ModerationResult[] Results);
file record ModerationResult(
    bool Flagged,
    [property: JsonPropertyName("categories")] Dictionary<string, bool> Categories,
    [property: JsonPropertyName("category_scores")] Dictionary<string, double> CategoryScores);
