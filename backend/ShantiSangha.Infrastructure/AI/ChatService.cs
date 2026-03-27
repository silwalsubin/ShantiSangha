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
    ILogger<ChatService> logger) : IChatService
{
    // How many recent messages to include directly in context
    private const int RecentMessageCount = 20;
    // How many past summaries to include
    private const int SummaryCount = 3;
    // How many saved insights to include
    private const int InsightCount = 5;

    public async IAsyncEnumerable<string> StreamResponseAsync(
        Guid userId,
        Guid conversationId,
        string userMessage,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        // Persist the user message immediately
        var userMsg = new Message
        {
            Id = Guid.NewGuid(),
            ConversationId = conversationId,
            Role = MessageRole.User,
            Content = userMessage,
            CreatedAt = DateTime.UtcNow
        };
        db.Messages.Add(userMsg);
        await db.SaveChangesAsync(cancellationToken);

        // Build context
        var chatHistory = await BuildChatHistoryAsync(userId, conversationId, userMessage, cancellationToken);

        // Stream response from OpenAI
        var chatCompletion = kernel.GetRequiredService<IChatCompletionService>();
        var responseChunks = new List<string>();

        await foreach (var chunk in chatCompletion.GetStreamingChatMessageContentsAsync(
            chatHistory,
            cancellationToken: cancellationToken))
        {
            var text = chunk.Content ?? string.Empty;
            if (!string.IsNullOrEmpty(text))
            {
                responseChunks.Add(text);
                yield return text;
            }
        }

        // Persist the full assistant response
        var fullResponse = string.Concat(responseChunks);
        if (!string.IsNullOrWhiteSpace(fullResponse))
        {
            var assistantMsg = new Message
            {
                Id = Guid.NewGuid(),
                ConversationId = conversationId,
                Role = MessageRole.Assistant,
                Content = fullResponse,
                CreatedAt = DateTime.UtcNow
            };
            db.Messages.Add(assistantMsg);

            // Update conversation timestamp
            var conversation = await db.Conversations.FindAsync([conversationId], cancellationToken);
            if (conversation is not null)
                conversation.UpdatedAt = DateTime.UtcNow;

            await db.SaveChangesAsync(CancellationToken.None);

            logger.LogDebug("Persisted assistant response for conversation {ConversationId}", conversationId);
        }
    }

    private async Task<ChatHistory> BuildChatHistoryAsync(
        Guid userId,
        Guid conversationId,
        string userMessage,
        CancellationToken cancellationToken)
    {
        // Fetch user profile for personalisation
        var profile = await db.Profiles.FirstOrDefaultAsync(p => p.UserId == userId, cancellationToken);

        // Recent past summaries for long-term memory
        var summaries = await db.Summaries
            .Where(s => s.UserId == userId && s.SourceType == SummarySourceType.Conversation)
            .OrderByDescending(s => s.CreatedAt)
            .Take(SummaryCount)
            .Select(s => s.Content)
            .ToListAsync(cancellationToken);

        // Saved insights the user has bookmarked
        var insights = await db.SavedInsights
            .Where(i => i.UserId == userId)
            .OrderByDescending(i => i.CreatedAt)
            .Take(InsightCount)
            .Select(i => i.Content)
            .ToListAsync(cancellationToken);

        // Recent mood for context
        var recentMoods = await db.MoodCheckins
            .Where(m => m.UserId == userId && m.CreatedAt >= DateTime.UtcNow.AddDays(-7))
            .OrderByDescending(m => m.CreatedAt)
            .Take(5)
            .ToListAsync(cancellationToken);

        string? moodSummary = null;
        if (recentMoods.Count > 0)
        {
            var avg = recentMoods.Average(m => m.Score);
            moodSummary = $"Over the past week their mood scores averaged {avg:F1}/10.";
        }

        var systemPrompt = SystemPrompt.WithContext(
            displayName: profile?.DisplayName,
            recentMoodSummary: moodSummary,
            savedInsights: insights,
            conversationSummaries: summaries);

        var history = new ChatHistory(systemPrompt);

        // Recent messages from this conversation (excluding the one we just added)
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
