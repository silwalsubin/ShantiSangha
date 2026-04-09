using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Insights.Data;
using ShantiSangha.Insights.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Insights.Jobs;

public class GenerateSummaryJob(
    InsightsDbContext db,
    IChatQueryService chatQuery,
    IJournalQueryService journalQuery,
    Kernel kernel,
    ILogger<GenerateSummaryJob> logger)
{
    public async Task RunForConversationAsync(Guid conversationId, Guid userId)
    {
        var messageCount = await chatQuery.GetMessageCountAsync(conversationId);
        if (messageCount < 4)
        {
            logger.LogDebug("Skipping summary for conversation {Id} -- too few messages", conversationId);
            return;
        }

        var recentExists = await db.Summaries.AnyAsync(s =>
            s.ConversationId == conversationId &&
            s.CreatedAt >= DateTime.UtcNow.AddMinutes(-10));

        if (recentExists)
        {
            logger.LogDebug("Skipping summary for conversation {Id} -- recent summary exists", conversationId);
            return;
        }

        var transcript = await chatQuery.GetConversationTranscriptAsync(conversationId);
        if (string.IsNullOrWhiteSpace(transcript)) return;

        var prompt = $"""
            Below is a wellness support conversation. Write a concise summary (3-5 sentences) that captures:
            - The main emotional themes the user explored
            - Any insights or shifts that emerged
            - The overall tone and direction of the conversation

            Do not include names. Do not evaluate or judge. Write in neutral, reflective language.

            Conversation:
            {transcript}
            """;

        var summary = await CallAiAsync(prompt);
        if (string.IsNullOrWhiteSpace(summary)) return;

        db.Summaries.Add(new Summary
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            SourceType = SummarySourceType.Conversation,
            ConversationId = conversationId,
            Content = summary,
            CreatedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync();
        logger.LogInformation("Generated summary for conversation {Id}", conversationId);
    }

    public async Task RunForJournalAsync(Guid journalId, Guid userId)
    {
        var journal = await journalQuery.GetJournalContentAsync(journalId);
        if (journal is null) return;

        var recentExists = await db.Summaries.AnyAsync(s =>
            s.JournalId == journalId &&
            s.CreatedAt >= DateTime.UtcNow.AddMinutes(-10));

        if (recentExists) return;

        var prompt = $"""
            Below is a personal journal entry. Write a concise summary (2-4 sentences) that captures:
            - The core emotional content
            - Any key themes or recurring thoughts
            - The emotional state reflected in the writing

            Write in neutral, reflective language. Do not evaluate or judge.

            Journal entry:
            {journal.Content}
            """;

        var summary = await CallAiAsync(prompt);
        if (string.IsNullOrWhiteSpace(summary)) return;

        db.Summaries.Add(new Summary
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            SourceType = SummarySourceType.Journal,
            JournalId = journalId,
            Content = summary,
            CreatedAt = DateTime.UtcNow
        });

        await db.SaveChangesAsync();
        logger.LogInformation("Generated summary for journal {Id}", journalId);
    }

    private async Task<string?> CallAiAsync(string prompt)
    {
        try
        {
            var chat = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory("You are a concise summarisation assistant.");
            history.AddUserMessage(prompt);
            var result = await chat.GetChatMessageContentAsync(history);
            return result.Content;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "AI call failed in GenerateSummaryJob");
            return null;
        }
    }
}
