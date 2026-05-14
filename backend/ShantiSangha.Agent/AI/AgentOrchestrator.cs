using System.Runtime.CompilerServices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using ShantiSangha.Agent.Data;
using ShantiSangha.Agent.Models;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Tools.Circles;
using ShantiSangha.Tools.Reflection;
using ShantiSangha.Tools.Reminders;

namespace ShantiSangha.Agent.AI;

public class AgentOrchestrator(
    Kernel kernel,
    IServiceProvider services,
    ICurrentUser currentUser,
    IProfileQueryService profileQuery,
    AgentDbContext db)
{
    private static readonly TimeSpan LoopTimeout = TimeSpan.FromSeconds(45);
    private const int HistoryReplayCount = 20;

    public async IAsyncEnumerable<string> StreamAsync(
        string userMessage,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var user = await currentUser.GetAsync()
            ?? throw new UnauthorizedAccessException("No authenticated user on this request.");

        string? displayName = null;
        try { displayName = await profileQuery.GetDisplayNameAsync(user.Id, cancellationToken); }
        catch { /* best-effort */ }

        // Persist the user turn FIRST so it survives an LLM failure mid-stream.
        var trimmed = userMessage.Trim();
        db.AgentMessages.Add(new AgentMessage
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Role = AgentMessageRole.User,
            Content = trimmed,
            CreatedAt = DateTime.UtcNow,
        });
        await db.SaveChangesAsync(cancellationToken);

        var scopedKernel = kernel.Clone();
        scopedKernel.Plugins.AddFromObject(
            services.GetRequiredService<RemindersTool>(),
            pluginName: "reminders");
        scopedKernel.Plugins.AddFromObject(
            services.GetRequiredService<CirclesTool>(),
            pluginName: "circles");
        scopedKernel.Plugins.AddFromObject(
            services.GetRequiredService<ReflectionTool>(),
            pluginName: "reflection");

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var history = new ChatHistory(AgentSystemPrompt.Build(today, displayName));

        // Replay the last N turns (including the user message we just saved)
        // so the LLM can resolve references like "move that to next Friday".
        var recent = await db.AgentMessages
            .Where(m => m.UserId == user.Id)
            .OrderByDescending(m => m.CreatedAt)
            .Take(HistoryReplayCount)
            .OrderBy(m => m.CreatedAt)
            .ToListAsync(cancellationToken);

        foreach (var msg in recent)
        {
            if (msg.Role == AgentMessageRole.User) history.AddUserMessage(msg.Content);
            else history.AddAssistantMessage(msg.Content);
        }

        var settings = new OpenAIPromptExecutionSettings
        {
            FunctionChoiceBehavior = FunctionChoiceBehavior.Auto(),
            Temperature = 0.2,
        };

        var completion = scopedKernel.GetRequiredService<IChatCompletionService>(AiModels.SmartServiceId);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(LoopTimeout);

        var assembled = new System.Text.StringBuilder();
        await foreach (var chunk in completion.GetStreamingChatMessageContentsAsync(
            history, settings, scopedKernel, timeout.Token))
        {
            var text = chunk.Content;
            if (string.IsNullOrEmpty(text)) continue;

            // Semantic Kernel's auto-invoke produces two assistant rounds
            // around a tool call (narration → tool → narration). The
            // streaming joins them without whitespace, so we get
            // "Let me do that now.Your reminder…". Detect the seam — prior
            // ends in sentence punctuation, next starts uppercase with no
            // leading whitespace — and insert a paragraph break.
            if (NeedsRoundBreak(assembled, text))
            {
                assembled.Append("\n\n");
                yield return "\n\n";
            }

            assembled.Append(text);
            yield return text;
        }

        var assistantContent = assembled.ToString().Trim();
        if (assistantContent.Length > 0)
        {
            db.AgentMessages.Add(new AgentMessage
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                Role = AgentMessageRole.Assistant,
                Content = assistantContent,
                CreatedAt = DateTime.UtcNow,
            });
            await db.SaveChangesAsync(CancellationToken.None);
        }
    }

    private static bool NeedsRoundBreak(System.Text.StringBuilder soFar, string next)
    {
        if (soFar.Length == 0 || next.Length == 0) return false;
        var lastChar = soFar[soFar.Length - 1];
        if (lastChar != '.' && lastChar != '!' && lastChar != '?') return false;
        var firstChar = next[0];
        return char.IsLetter(firstChar) && char.IsUpper(firstChar);
    }
}
