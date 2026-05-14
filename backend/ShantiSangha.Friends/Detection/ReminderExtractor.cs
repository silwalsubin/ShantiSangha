using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using ShantiSangha.Shared;

namespace ShantiSangha.Friends.Detection;

/// <summary>
/// Result of a high-confidence reminder extraction. Null when the LLM
/// returns low confidence, malformed JSON, or a date it can't resolve.
/// </summary>
public record ReminderExtraction(string Label, DateOnly Date, string Recurrence);

public interface IReminderExtractor
{
    Task<ReminderExtraction?> ExtractAsync(string messageBody, DateOnly today, CancellationToken ct = default);
}

internal sealed class ReminderExtractor(Kernel kernel, ILogger<ReminderExtractor> logger) : IReminderExtractor
{
    public async Task<ReminderExtraction?> ExtractAsync(
        string messageBody, DateOnly today, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(messageBody)) return null;

        var systemPrompt = $$"""
            You read one chat message and decide if it contains a single
            actionable reminder the speaker would want scheduled.

            Today is {{today:yyyy-MM-dd}} ({{today.DayOfWeek}}).

            Output STRICT JSON only — no prose, no markdown — matching:
            {
              "label":      string, 1-80 chars, short imperative ("call mom", "renew passport"),
              "date":       string, yyyy-MM-dd, when the user should be reminded,
              "recurrence": "none" | "yearly",
              "confidence": "high" | "medium" | "low"
            }

            Set confidence to "high" only when:
              - the message clearly proposes something to remember
              - AND a specific date can be resolved without guessing
              - AND the label would be useful out of context

            "yearly" only for birthdays, anniversaries, recurring annual events.

            Past tense, hypotheticals, jokes, vague mentions → "low".
            """;

        var history = new ChatHistory(systemPrompt);
        history.AddUserMessage(messageBody);

        var settings = new OpenAIPromptExecutionSettings
        {
            Temperature = 0.0,
            ResponseFormat = "json_object",
            MaxTokens = 200,
        };

        try
        {
            var completion = kernel.GetRequiredService<IChatCompletionService>(AiModels.FastServiceId);
            var result = await completion.GetChatMessageContentAsync(history, settings, kernel, ct);
            var raw = result.Content;
            if (string.IsNullOrWhiteSpace(raw)) return null;

            var parsed = JsonSerializer.Deserialize<LlmResponse>(raw, JsonOptions);
            if (parsed is null) return null;

            if (!string.Equals(parsed.Confidence, "high", StringComparison.OrdinalIgnoreCase))
                return null;

            if (string.IsNullOrWhiteSpace(parsed.Label) || parsed.Label.Length > 80)
                return null;

            if (!DateOnly.TryParse(parsed.Date, out var date))
                return null;

            var recurrence = parsed.Recurrence?.ToLowerInvariant() switch
            {
                "yearly" => "yearly",
                _ => "none",
            };

            return new ReminderExtraction(parsed.Label.Trim(), date, recurrence);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ReminderExtractor failed; treating as no-suggestion");
            return null;
        }
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private sealed class LlmResponse
    {
        [JsonPropertyName("label")] public string? Label { get; set; }
        [JsonPropertyName("date")] public string? Date { get; set; }
        [JsonPropertyName("recurrence")] public string? Recurrence { get; set; }
        [JsonPropertyName("confidence")] public string? Confidence { get; set; }
    }
}
