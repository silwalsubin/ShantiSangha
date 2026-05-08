using System.Runtime.CompilerServices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Models;
using ShantiSangha.Chat.Safety;
using ShantiSangha.Chat.Services;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Chat.AI;

public class ChatService(
    ChatDbContext db,
    Kernel kernel,
    ISafetyService safety,
    IGoalQueryService goalQuery,
    IReflectionQueryService reflectionQuery,
    IProfileQueryService profileQuery,
    IEventBus eventBus,
    ILogger<ChatService> logger) : IChatService
{
    private const int RecentMessageCount = 20;

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

        // --- Step 3: Build context and stream AI response ---
        var chatHistory = await BuildChatHistoryAsync(userId, conversationId, cancellationToken, userMessage);
        var chatCompletion = kernel.GetRequiredService<IChatCompletionService>(AiModels.SmartServiceId);
        var responseChunks = new List<string>();

        await foreach (var chunk in chatCompletion.GetStreamingChatMessageContentsAsync(
            chatHistory, cancellationToken: cancellationToken))
        {
            var text = chunk.Content ?? string.Empty;
            if (!string.IsNullOrEmpty(text))
            {
                responseChunks.Add(text);
                yield return text;
            }
        }

        var fullResponse = string.Concat(responseChunks);

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
        // Load all context in parallel — each task is fault-tolerant so a single
        // failure doesn't kill the entire conversation.
        string? displayName = null;
        string? todaysReflection = null;
        IReadOnlyList<GoalSummaryDto> goalDtos = [];

        try
        {
            var displayNameTask = profileQuery.GetDisplayNameAsync(userId, cancellationToken);
            var goalsTask = goalQuery.GetActiveGoalsForContextAsync(userId, ct: cancellationToken);
            var reflectionTask = reflectionQuery.GetRecentReflectionAsync(userId, cancellationToken);

            await Task.WhenAll(displayNameTask, goalsTask, reflectionTask);

            displayName = displayNameTask.Result;
            goalDtos = goalsTask.Result;
            todaysReflection = reflectionTask.Result;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to load some context for conversation {ConversationId} — continuing with partial context", conversationId);
        }

        var goalContexts = goalDtos.Select(g => new GoalContext(
            Title: g.Title,
            Type: g.Type,
            CurrentStreak: g.CurrentStreak,
            LongestStreak: g.LongestStreak,
            CheckedInToday: g.CheckedInToday,
            DaysRemaining: g.DaysRemaining,
            IsCompleted: g.IsCompleted,
            DeeperWhy: g.DeeperWhy)).ToList();

        var systemPrompt = SystemPrompt.WithContext(
            displayName: displayName,
            todaysReflection: todaysReflection,
            goals: goalContexts);

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
}
