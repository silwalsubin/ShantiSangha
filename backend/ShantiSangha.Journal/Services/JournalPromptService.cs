using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Journal.Services;

/// One gentle journaling question drawn from the user's own recent words
/// (via the Memory module). Serves the editor's placeholder — the client
/// falls back to its static prompts when this returns null.
public class JournalPromptService(
    Kernel kernel,
    IMemoryQueryService memoryQuery,
    ILogger<JournalPromptService> logger)
{
    public async Task<string?> GetPromptAsync(Guid userId, CancellationToken ct = default)
    {
        try
        {
            var recent = await memoryQuery.GetRecentAsync(userId, 5, ct);
            if (recent.Count == 0) return null;

            var fragments = string.Join("\n", recent.Select(h =>
            {
                var flat = h.Content.ReplaceLineEndings(" ").Trim();
                if (flat.Length > 300) flat = flat[..300] + "…";
                return $"- [{h.OccurredAt:MMMM d}] {flat}";
            }));

            var history = new ChatHistory("""
                You write a single opening question for a private journal, addressed to the
                writer, drawn from fragments of their own recent journals and reflections.

                Rules:
                - ONE question only, 25 words or fewer, second person, present tense.
                - Pick up a genuine thread from the fragments — a feeling, a worry, a
                  recurring subject — and gently invite them deeper. Never summarize the
                  fragments back at them.
                - Warm and unhurried, never clinical, never cheerful-coach. No preamble,
                  no quotation marks, no emojis — output the question and nothing else.
                - If the fragments hold nothing worth returning to, ask a simple grounding
                  question about today instead.
                """);
            history.AddUserMessage($"Their recent fragments:\n{fragments}");

            var chat = kernel.GetRequiredService<IChatCompletionService>(AiModels.FastServiceId);
            var result = await chat.GetChatMessageContentAsync(history, cancellationToken: ct);

            var prompt = result.Content?.Trim().Trim('"');
            return string.IsNullOrWhiteSpace(prompt) ? null : prompt;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Journal prompt generation failed for user {UserId} — client will fall back", userId);
            return null;
        }
    }
}
