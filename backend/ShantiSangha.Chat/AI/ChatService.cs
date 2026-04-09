using System.Runtime.CompilerServices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Models;
using ShantiSangha.Chat.Safety;
using ShantiSangha.Chat.Services;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Chat.AI;

public class ChatService(
    ChatDbContext db,
    Kernel kernel,
    ISafetyService safety,
    IInsightQueryService insightQuery,
    ISummaryQueryService summaryQuery,
    IGoalQueryService goalQuery,
    IMoodQueryService moodQuery,
    IProfileQueryService profileQuery,
    IEventBus eventBus,
    ILogger<ChatService> logger) : IChatService
{
    private const int RecentMessageCount = 20;
    private const int SummaryCount = 3;
    private const int InsightCount = 5;

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
        var chatCompletion = kernel.GetRequiredService<IChatCompletionService>();
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
        var displayNameTask = profileQuery.GetDisplayNameAsync(userId, cancellationToken);
        var summariesTask = summaryQuery.GetRecentSummariesAsync(userId, SummaryCount, cancellationToken);
        var moodTask = moodQuery.GetRecentMoodSummaryAsync(userId, 7, cancellationToken);
        var goalsTask = goalQuery.GetActiveGoalsForContextAsync(userId, cancellationToken);

        await Task.WhenAll(displayNameTask, summariesTask, moodTask, goalsTask);

        var displayName = displayNameTask.Result;
        var summaries = summariesTask.Result;
        var moodSummary = moodTask.Result;
        var goalDtos = goalsTask.Result;

        // Use semantic search when we have a message to query with, otherwise fall back to recency
        IReadOnlyList<string> insights;
        if (!string.IsNullOrWhiteSpace(currentMessage))
        {
            insights = await insightQuery.SearchInsightsAsync(userId, currentMessage, InsightCount, cancellationToken);

            if (insights.Count == 0)
                insights = await insightQuery.GetRecentInsightsAsync(userId, InsightCount, cancellationToken);
        }
        else
        {
            insights = await insightQuery.GetRecentInsightsAsync(userId, InsightCount, cancellationToken);
        }

        string? moodSummaryText = moodSummary is not null
            ? $"Over the past week their mood scores averaged {moodSummary.AverageScore:F1}/10."
            : null;

        var goalContexts = goalDtos.Select(g => new GoalContext(
            Title: g.Title,
            Type: g.Type,
            CurrentStreak: g.CurrentStreak,
            LongestStreak: 0,
            CheckedInToday: null,
            DaysRemaining: null,
            IsCompleted: false,
            DeeperWhy: g.DeeperWhy)).ToList();

        var systemPrompt = SystemPrompt.WithContext(
            displayName: displayName,
            recentMoodSummary: moodSummaryText,
            savedInsights: insights,
            conversationSummaries: summaries,
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
