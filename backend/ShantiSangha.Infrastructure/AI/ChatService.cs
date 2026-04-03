using System.Runtime.CompilerServices;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Core.Models;
using ShantiSangha.Core.Services;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Infrastructure.AI;

public class ChatService(
    AppDbContext db,
    Kernel kernel,
    ISafetyService safety,
    ISemanticSearchService semanticSearch,
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
            await safety.LogEventAsync(userId, nameof(SafetyEventType.CrisisKeywordDetected),
                userMessage, inputCheck.Reason, conversationId, cancellationToken);

            logger.LogWarning("Crisis signal in conversation {ConversationId}", conversationId);
            yield return SupportResources.CrisisResponse;
            yield break;
        }

        if (inputCheck.Outcome == SafetyCheckOutcome.Flagged)
        {
            await safety.LogEventAsync(userId, nameof(SafetyEventType.ModerationFlagged),
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
            await safety.LogEventAsync(userId, nameof(SafetyEventType.ResponseFlagged),
                fullResponse, outputCheck.Reason, conversationId, CancellationToken.None);

            logger.LogError("AI response failed output safety check in conversation {ConversationId}", conversationId);

            // Yield the fallback in place of the streamed response that we already sent
            // In practice the client should replace the partial response when it receives this event
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
        }
    }

    private async Task<ChatHistory> BuildChatHistoryAsync(
        Guid userId,
        Guid conversationId,
        CancellationToken cancellationToken,
        string? currentMessage = null)
    {
        var profile = await db.Profiles
            .FirstOrDefaultAsync(p => p.UserId == userId, cancellationToken);

        var summaries = await db.Summaries
            .Where(s => s.UserId == userId && s.SourceType == SummarySourceType.Conversation)
            .OrderByDescending(s => s.CreatedAt)
            .Take(SummaryCount)
            .Select(s => s.Content)
            .ToListAsync(cancellationToken);

        // Use semantic search when we have a message to query with, otherwise fall back to recency
        List<string> insights;
        if (!string.IsNullOrWhiteSpace(currentMessage))
        {
            var semanticInsights = await semanticSearch.SearchInsightsAsync(
                userId, currentMessage, InsightCount, cancellationToken);
            insights = semanticInsights.Select(r => r.Content).ToList();

            // If no embeddings exist yet (early user), fall back to recency
            if (insights.Count == 0)
            {
                insights = await db.SavedInsights
                    .Where(i => i.UserId == userId)
                    .OrderByDescending(i => i.CreatedAt)
                    .Take(InsightCount)
                    .Select(i => i.Content)
                    .ToListAsync(cancellationToken);
            }
        }
        else
        {
            insights = await db.SavedInsights
                .Where(i => i.UserId == userId)
                .OrderByDescending(i => i.CreatedAt)
                .Take(InsightCount)
                .Select(i => i.Content)
                .ToListAsync(cancellationToken);
        }

        var recentMoods = await db.MoodCheckins
            .Where(m => m.UserId == userId && m.CreatedAt >= DateTime.UtcNow.AddDays(-7))
            .OrderByDescending(m => m.CreatedAt)
            .Take(5)
            .ToListAsync(cancellationToken);

        string? moodSummary = recentMoods.Count > 0
            ? $"Over the past week their mood scores averaged {recentMoods.Average(m => m.Score):F1}/10."
            : null;

        var goalContexts = await BuildGoalContextAsync(userId, cancellationToken);

        var systemPrompt = SystemPrompt.WithContext(
            displayName: profile?.DisplayName,
            recentMoodSummary: moodSummary,
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

    private async Task<List<GoalContext>> BuildGoalContextAsync(
        Guid userId, CancellationToken cancellationToken)
    {
        var goals = await db.Goals
            .Where(g => g.UserId == userId && g.ArchivedAt == null)
            .Include(g => g.CheckIns)
            .OrderBy(g => g.CreatedAt)
            .ToListAsync(cancellationToken);

        if (goals.Count == 0) return [];

        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        return goals.Select(g =>
        {
            if (g.Type == GoalType.Recurring)
            {
                var (current, longest) = ComputeStreaks(g.CheckIns, today);
                var todayCheckIn = g.CheckIns.FirstOrDefault(c => c.Date == today);

                return new GoalContext(
                    Title: g.Title,
                    Type: "Recurring",
                    CurrentStreak: current,
                    LongestStreak: longest,
                    CheckedInToday: todayCheckIn?.Completed,
                    DaysRemaining: null,
                    IsCompleted: false,
                    DeeperWhy: g.DeeperWhy);
            }
            else
            {
                int? daysRemaining = g.TargetDate.HasValue
                    ? g.TargetDate.Value.DayNumber - today.DayNumber
                    : null;

                return new GoalContext(
                    Title: g.Title,
                    Type: "OneTime",
                    CurrentStreak: 0,
                    LongestStreak: 0,
                    CheckedInToday: null,
                    DaysRemaining: daysRemaining,
                    IsCompleted: g.CompletedAt.HasValue,
                    DeeperWhy: g.DeeperWhy);
            }
        }).ToList();
    }

    private static (int CurrentStreak, int LongestStreak) ComputeStreaks(
        ICollection<GoalCheckIn> checkIns, DateOnly today)
    {
        if (checkIns.Count == 0) return (0, 0);

        var completedDates = checkIns
            .Where(c => c.Completed)
            .Select(c => c.Date)
            .ToHashSet();

        var currentStreak = 0;
        var date = today;
        while (completedDates.Contains(date))
        {
            currentStreak++;
            date = date.AddDays(-1);
        }

        if (completedDates.Count == 0) return (0, 0);

        var sorted = completedDates.OrderBy(d => d).ToList();
        var longestStreak = 1;
        var streak = 1;

        for (var i = 1; i < sorted.Count; i++)
        {
            if (sorted[i].DayNumber - sorted[i - 1].DayNumber == 1)
            {
                streak++;
                if (streak > longestStreak) longestStreak = streak;
            }
            else
            {
                streak = 1;
            }
        }

        return (currentStreak, longestStreak);
    }
}
