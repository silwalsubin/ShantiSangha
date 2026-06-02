using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using ShantiSangha.Agent.Contracts;
using ShantiSangha.Shared;

namespace ShantiSangha.Agent.AI;

/// <summary>
/// A cheap second pass over a finished assistant reply: proposes up to 3
/// tappable follow-ups ("quick actions") the user is likely to want next, so a
/// lazy-typing user can tap instead of type. Runs on the fast model
/// (gpt-4o-mini) AFTER the main reply has streamed, so it never delays prose.
/// Returns an empty list whenever there's no clearly useful next step — which
/// is common and correct. Best-effort: any failure yields no chips.
/// </summary>
public sealed class QuickActionSuggester(Kernel kernel, ILogger<QuickActionSuggester> logger)
{
    private const int MaxActions = 3;

    public async Task<IReadOnlyList<QuickAction>> SuggestAsync(
        string userMessage, string assistantReply, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(assistantReply))
            return Array.Empty<QuickAction>();

        const string systemPrompt = """
            You suggest tappable follow-up buttons for ShantiSangha's in-app
            assistant, which manages the user's reminders and the people in their
            circle. Given the user's last message and the assistant's reply,
            propose the most likely next actions the user would tap next.

            Output STRICT JSON only — no prose, no markdown — matching:
            {
              "actions": [
                { "label": string, "prompt": string }
              ]
            }

            - "label": the short button text the user sees. Max 24 chars, no
              trailing punctuation (e.g. "Add a new one", "Remind me June 14",
              "Share with someone").
            - "prompt": the full message sent as the user when the button is
              tapped. Write it in the user's voice and include enough context to
              act on its own (e.g. "Remind me to cancel Paramount on May 31").
            - At most 3 actions. Fewer is better.
            - Return {"actions": []} whenever there is no clearly useful next
              step. This is common and expected — most replies need none. Do NOT
              invent actions just to fill the list, and never suggest things the
              assistant can't do (journaling, voice notes, messaging friends).
            """;

        var history = new ChatHistory(systemPrompt);
        history.AddUserMessage(
            $"User said:\n{userMessage}\n\nAssistant replied:\n{assistantReply}");

        var settings = new OpenAIPromptExecutionSettings
        {
            Temperature = 0.3,
            ResponseFormat = "json_object",
            MaxTokens = 200,
        };

        try
        {
            var completion = kernel.GetRequiredService<IChatCompletionService>(AiModels.FastServiceId);
            var result = await completion.GetChatMessageContentAsync(history, settings, kernel, ct);
            var raw = result.Content;
            if (string.IsNullOrWhiteSpace(raw)) return Array.Empty<QuickAction>();

            var parsed = JsonSerializer.Deserialize<LlmResponse>(raw, JsonOptions);
            if (parsed?.Actions is null || parsed.Actions.Count == 0)
                return Array.Empty<QuickAction>();

            var actions = new List<QuickAction>(MaxActions);
            foreach (var a in parsed.Actions)
            {
                if (string.IsNullOrWhiteSpace(a.Label) || string.IsNullOrWhiteSpace(a.Prompt))
                    continue;

                var label = a.Label.Trim();
                if (label.Length > 40) label = label[..40].TrimEnd();

                actions.Add(new QuickAction(label, a.Prompt.Trim()));
                if (actions.Count == MaxActions) break;
            }

            return actions;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "QuickActionSuggester failed; treating as no-suggestion");
            return Array.Empty<QuickAction>();
        }
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private sealed class LlmResponse
    {
        [JsonPropertyName("actions")] public List<Action>? Actions { get; set; }
    }

    private sealed class Action
    {
        [JsonPropertyName("label")] public string? Label { get; set; }
        [JsonPropertyName("prompt")] public string? Prompt { get; set; }
    }
}
