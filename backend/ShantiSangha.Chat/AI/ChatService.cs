using System.Runtime.CompilerServices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Models;
using ShantiSangha.Chat.Services;
using ShantiSangha.Shared;
using ShantiSangha.Shared.AI;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Tools;
using ShantiSangha.Tools.AgentFeedback;

namespace ShantiSangha.Chat.AI;

public class ChatService(
    ChatDbContext db,
    Kernel kernel,
    IServiceProvider services,
    ISafetyService safety,
    IProfileQueryService profileQuery,
    IMemoryQueryService memoryQuery,
    AgentTurnContext turnContext,
    IEventBus eventBus,
    ILogger<ChatService> logger) : IChatService
{
    private const int RecentMessageCount = 20;

    // Generous ceiling for a reflective reply that may also cross a tool
    // round or two — protects against a hung tool loop, not a slow answer.
    private static readonly TimeSpan LoopTimeout = TimeSpan.FromSeconds(60);

    public async IAsyncEnumerable<string> StreamResponseAsync(
        Guid userId,
        Guid conversationId,
        string userMessage,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        // --- Step 1: Input safety check ---
        var inputCheck = await safety.CheckInputAsync(userMessage, cancellationToken);

        if (inputCheck.Outcome == SafetyCheckOutcome.Crisis)
        {
            await safety.LogEventAsync(userId, "CrisisKeywordDetected",
                userMessage, inputCheck.Reason, conversationId, cancellationToken);

            logger.LogWarning("Crisis signal in conversation {ConversationId}", conversationId);
            yield return SupportResources.CrisisResponse;
            yield break;
        }

        if (inputCheck.Outcome == SafetyCheckOutcome.Flagged)
        {
            await safety.LogEventAsync(userId, "ModerationFlagged",
                userMessage, inputCheck.Reason, conversationId, cancellationToken);

            logger.LogWarning("Moderation flagged input in conversation {ConversationId}", conversationId);
            yield return SupportResources.FlaggedResponse;
            yield break;
        }

        // --- Step 2: Persist user message ---
        var userMsg = new Message
        {
            Id = Guid.NewGuid(),
            ConversationId = conversationId,
            Role = MessageRole.User,
            Content = userMessage.Trim(),
            CreatedAt = DateTime.UtcNow
        };
        db.Messages.Add(userMsg);
        await db.SaveChangesAsync(cancellationToken);

        // Any feedback the LLM records this turn attributes back to the exact
        // message that triggered it.
        turnContext.CurrentUserMessageId = userMsg.Id;

        // --- Step 3: Build context and stream AI response (one mind: the
        // companion carries the shared tool roster too) ---
        var chatHistory = await BuildChatHistoryAsync(userId, conversationId, cancellationToken, userMessage);

        var toolsKernel = kernel.CloneWithShantiSanghaTools(services);
        var settings = new OpenAIPromptExecutionSettings
        {
            FunctionChoiceBehavior = FunctionChoiceBehavior.Auto(),
        };
        var chatCompletion = toolsKernel.GetRequiredService<IChatCompletionService>(AiModels.SmartServiceId);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(LoopTimeout);

        var assembled = new System.Text.StringBuilder();
        await foreach (var chunk in chatCompletion.GetStreamingChatMessageContentsAsync(
            chatHistory, settings, toolsKernel, timeout.Token))
        {
            var text = chunk.Content;
            if (string.IsNullOrEmpty(text)) continue;

            if (StreamSeams.NeedsRoundBreak(assembled, text))
            {
                assembled.Append("\n\n");
                yield return "\n\n";
            }

            assembled.Append(text);
            yield return text;
        }

        var fullResponse = assembled.ToString();

        // --- Step 4: Output safety check ---
        var outputCheck = await safety.CheckOutputAsync(fullResponse, cancellationToken);

        if (outputCheck.Outcome != SafetyCheckOutcome.Clear)
        {
            await safety.LogEventAsync(userId, "ResponseFlagged",
                fullResponse, outputCheck.Reason, conversationId, CancellationToken.None);

            logger.LogError("AI response failed output safety check in conversation {ConversationId}", conversationId);

            yield return SupportResources.ResponseFallback;
            fullResponse = SupportResources.ResponseFallback;
        }

        // --- Step 5: Persist assistant message ---
        if (!string.IsNullOrWhiteSpace(fullResponse))
        {
            var assistantMsg = new Message
            {
                Id = Guid.NewGuid(),
                ConversationId = conversationId,
                Role = MessageRole.Assistant,
                Content = fullResponse.Trim(),
                CreatedAt = DateTime.UtcNow
            };
            db.Messages.Add(assistantMsg);

            var conversation = await db.Conversations.FindAsync([conversationId], CancellationToken.None);
            if (conversation is not null)
                conversation.UpdatedAt = DateTime.UtcNow;

            await db.SaveChangesAsync(CancellationToken.None);

            // --- Step 6: Publish event for downstream processing ---
            var messageCount = await db.Messages.CountAsync(m => m.ConversationId == conversationId, CancellationToken.None);
            var lastTwo = await db.Messages
                .Where(m => m.ConversationId == conversationId)
                .OrderByDescending(m => m.CreatedAt)
                .Take(2)
                .Select(m => m.Id)
                .ToListAsync(CancellationToken.None);

            await eventBus.PublishAsync(new MessagesSavedEvent(
                conversationId, userId, messageCount, lastTwo), CancellationToken.None);
        }
    }

    private async Task<ChatHistory> BuildChatHistoryAsync(
        Guid userId,
        Guid conversationId,
        CancellationToken cancellationToken,
        string? currentMessage = null)
    {
        var (displayName, timezone) = await LoadProfileAsync(userId, conversationId, cancellationToken);

        string? memories = null;
        try
        {
            if (!string.IsNullOrWhiteSpace(currentMessage))
            {
                var hits = await memoryQuery.SearchAsync(
                    userId, currentMessage, UnifiedPrompt.MemoryTopK,
                    excludeConversationId: conversationId,
                    ct: cancellationToken);

                memories = UnifiedPrompt.FormatMemories(hits);
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to load memories for conversation {ConversationId} — continuing without", conversationId);
        }

        var systemPrompt = UnifiedPrompt.Build(
            UserClock.TodayFor(timezone), displayName, memories, PromptSurface.Reflect);

        var history = new ChatHistory(systemPrompt);

        var recentMessages = await db.Messages
            .Where(m => m.ConversationId == conversationId)
            .OrderByDescending(m => m.CreatedAt)
            .Take(RecentMessageCount)
            .OrderBy(m => m.CreatedAt)
            .ToListAsync(cancellationToken);

        foreach (var msg in recentMessages)
        {
            if (msg.Role == MessageRole.User)
                history.AddUserMessage(msg.Content);
            else
                history.AddAssistantMessage(msg.Content);
        }

        return history;
    }

    public async IAsyncEnumerable<string> StreamOpenerAsync(
        Guid userId,
        Guid conversationId,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        // The opener belongs only at the very start — if anything has been
        // said (including a previous opener), stay quiet.
        var hasMessages = await db.Messages
            .AnyAsync(m => m.ConversationId == conversationId, cancellationToken);
        if (hasMessages) yield break;

        var (displayName, timezone) = await LoadProfileAsync(userId, conversationId, cancellationToken);

        string? memories = null;
        try
        {
            var recent = await memoryQuery.GetRecentAsync(userId, UnifiedPrompt.MemoryTopK, cancellationToken);
            memories = UnifiedPrompt.FormatMemories(recent);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to load opener context for conversation {ConversationId} — continuing with partial context", conversationId);
        }

        // The opener speaks first and acts on nothing — no tools needed.
        var systemPrompt = UnifiedPrompt.Build(
                UserClock.TodayFor(timezone), displayName, memories, PromptSurface.Reflect)
            + "\n\n---\n\n" + UnifiedPrompt.OpenerInstruction;

        var history = new ChatHistory(systemPrompt);
        history.AddUserMessage("(The person has just opened the conversation and hasn't said anything yet. Greet them first.)");

        var chatCompletion = kernel.GetRequiredService<IChatCompletionService>(AiModels.SmartServiceId);
        var responseChunks = new List<string>();

        await foreach (var chunk in chatCompletion.GetStreamingChatMessageContentsAsync(
            history, cancellationToken: cancellationToken))
        {
            var text = chunk.Content ?? string.Empty;
            if (!string.IsNullOrEmpty(text))
            {
                responseChunks.Add(text);
                yield return text;
            }
        }

        var fullResponse = string.Concat(responseChunks);

        var outputCheck = await safety.CheckOutputAsync(fullResponse, cancellationToken);
        if (outputCheck.Outcome != SafetyCheckOutcome.Clear)
        {
            await safety.LogEventAsync(userId, "ResponseFlagged",
                fullResponse, outputCheck.Reason, conversationId, CancellationToken.None);
            logger.LogError("Opener failed output safety check in conversation {ConversationId}", conversationId);
            yield return SupportResources.ResponseFallback;
            fullResponse = SupportResources.ResponseFallback;
        }

        if (!string.IsNullOrWhiteSpace(fullResponse))
        {
            db.Messages.Add(new Message
            {
                Id = Guid.NewGuid(),
                ConversationId = conversationId,
                Role = MessageRole.Assistant,
                Content = fullResponse.Trim(),
                CreatedAt = DateTime.UtcNow
            });
            await db.SaveChangesAsync(CancellationToken.None);
        }
    }

    private async Task<(string? DisplayName, string? Timezone)> LoadProfileAsync(
        Guid userId, Guid conversationId, CancellationToken ct)
    {
        string? displayName = null;
        string? timezone = null;
        try
        {
            displayName = await profileQuery.GetDisplayNameAsync(userId, ct);
            timezone = await profileQuery.GetTimezoneAsync(userId, ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to load profile context for conversation {ConversationId} — continuing with partial context", conversationId);
        }
        return (displayName, timezone);
    }
}
