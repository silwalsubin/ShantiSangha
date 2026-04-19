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
using ShantiSangha.Shared.Jyotish;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Chat.AI;

public class ChatService(
    ChatDbContext db,
    Kernel kernel,
    ISafetyService safety,
    IInsightQueryService insightQuery,
    ISummaryQueryService summaryQuery,
    IGoalQueryService goalQuery,
    IReflectionQueryService reflectionQuery,
    IProfileQueryService profileQuery,
    IJyotishContextService jyotishService,
    IJyotishKnowledgeService jyotishKnowledge,
    IChartReadingService chartReadingService,
    IEventBus eventBus,
    ILogger<ChatService> logger) : IChatService
{
    private const int RecentMessageCount = 20;
    private const int SummaryCount = 3;
    private const int InsightCount = 5;
    private const int PassageCount = 4;

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
        // Determine conversation type up-front — chart conversations use a
        // tighter, corpus-bounded prompt; general conversations use the
        // broader spiritual-companion prompt with full personal context.
        var conversationType = await db.Conversations
            .Where(c => c.Id == conversationId)
            .Select(c => c.Type)
            .FirstOrDefaultAsync(cancellationToken) ?? ConversationType.General;
        var isChart = conversationType == ConversationType.Chart;

        // Load all context in parallel — each task is fault-tolerant so a single
        // failure (e.g. embedding search) doesn't kill the entire conversation.
        string? displayName = null;
        string? todaysReflection = null;
        IReadOnlyList<string> summaries = [];
        IReadOnlyList<string> journalSummaries = [];
        IReadOnlyList<GoalSummaryDto> goalDtos = [];
        IReadOnlyList<string> insights = [];
        JyotishContext? jyotish = null;
        IReadOnlyList<JyotishPassage> passages = [];

        try
        {
            // For chart conversations we skip goals / journal / insight / reflection
            // context entirely — they dilute the corpus grounding and aren't what
            // the person is asking about. Chart chat is Jyotish-only.
            var displayNameTask = profileQuery.GetDisplayNameAsync(userId, cancellationToken);
            var jyotishTask = jyotishService.GetContextAsync(userId, DateOnly.FromDateTime(DateTime.UtcNow), cancellationToken);

            if (isChart)
            {
                await Task.WhenAll(displayNameTask, jyotishTask);
                displayName = displayNameTask.Result;
                jyotish = jyotishTask.Result;
            }
            else
            {
                var summariesTask = summaryQuery.GetRecentSummariesAsync(userId, SummaryCount, cancellationToken);
                var journalSummariesTask = summaryQuery.GetRecentJournalSummariesAsync(userId, SummaryCount, cancellationToken);
                var goalsTask = goalQuery.GetActiveGoalsForContextAsync(userId, ct: cancellationToken);
                var reflectionTask = reflectionQuery.GetRecentReflectionAsync(userId, cancellationToken);

                await Task.WhenAll(displayNameTask, summariesTask, journalSummariesTask, goalsTask, reflectionTask, jyotishTask);

                displayName = displayNameTask.Result;
                summaries = summariesTask.Result;
                journalSummaries = journalSummariesTask.Result;
                goalDtos = goalsTask.Result;
                todaysReflection = reflectionTask.Result;
                jyotish = jyotishTask.Result;
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to load some context for conversation {ConversationId} — continuing with partial context", conversationId);
        }

        if (!isChart)
        {
            try
            {
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
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to load insights for conversation {ConversationId} — continuing without insights", conversationId);
            }
        }

        // Retrieve Jyotish passages. Chart conversations rely exclusively on
        // signature-based retrieval from the user's actual chart. General
        // conversations supplement with semantic search for thematic gaps.
        try
        {
            var chartPassages = Array.Empty<JyotishPassage>() as IReadOnlyList<JyotishPassage>;
            if (jyotish is not null)
            {
                var signatures = jyotish.DeriveSignatures().Distinct(StringComparer.OrdinalIgnoreCase).ToList();
                if (signatures.Count > 0)
                    chartPassages = await jyotishKnowledge.GetPassagesAsync(signatures, cancellationToken);
            }

            IReadOnlyList<JyotishPassage> semanticPassages = Array.Empty<JyotishPassage>();
            if (!isChart && !string.IsNullOrWhiteSpace(currentMessage))
                semanticPassages = await jyotishKnowledge.SearchSemanticAsync(currentMessage, topK: PassageCount, ct: cancellationToken);

            // Topic routing: on chart conversations, rerank chart passages so
            // the ones matching the user's question topic bubble to the top.
            // This is what makes "how does my chart say about investing?"
            // prioritize wealth/career-house passages over, e.g., siblings.
            if (isChart && !string.IsNullOrWhiteSpace(currentMessage) && chartPassages.Count > 0)
                chartPassages = ChartTopicRouter.Rerank(currentMessage!, chartPassages);

            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var merged = new List<JyotishPassage>();
            foreach (var p in chartPassages.Concat(semanticPassages))
            {
                if (seen.Add(p.Id))
                    merged.Add(p);
            }
            passages = merged;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Jyotish RAG retrieval failed for conversation {ConversationId} — continuing without passages", conversationId);
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

        // Chart conversations read from the pre-composed chart reading when
        // one exists. If no reading is cached yet, we skip it here (lazy-
        // generating on every chat turn would be too expensive); the iOS
        // chart page's GET /api/jyotish/reading triggers generation
        // separately when the user opens the chart.
        ChartReading? chartReading = null;
        if (isChart)
        {
            try
            {
                chartReading = await chartReadingService.GetAsync(userId, cancellationToken);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to load chart reading for conversation {ConversationId}", conversationId);
            }
        }

        var systemPrompt = isChart
            ? SystemPrompt.ForChart(
                displayName: displayName,
                jyotish: jyotish,
                jyotishPassages: passages,
                reading: chartReading)
            : SystemPrompt.WithContext(
                displayName: displayName,
                todaysReflection: todaysReflection,
                savedInsights: insights,
                conversationSummaries: summaries,
                journalSummaries: journalSummaries,
                goals: goalContexts,
                jyotish: jyotish,
                jyotishPassages: passages);

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
