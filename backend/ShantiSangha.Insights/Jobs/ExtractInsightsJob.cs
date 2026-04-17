using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Insights.Data;
using ShantiSangha.Insights.Models;
using ShantiSangha.Insights.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Insights.Jobs;

public class ExtractInsightsJob(
    InsightsDbContext db,
    Kernel kernel,
    IInsightQueryService insightQuery,
    IPushNotificationService pushService,
    ILogger<ExtractInsightsJob> logger)
{
    public async Task RunAsync(Guid sourceId, SummarySourceType sourceType, Guid userId)
    {
        var summary = await db.Summaries
            .Where(s => sourceType == SummarySourceType.Conversation
                ? s.ConversationId == sourceId
                : s.JournalId == sourceId)
            .OrderByDescending(s => s.CreatedAt)
            .FirstOrDefaultAsync();

        if (summary is null)
        {
            logger.LogDebug("No summary found for {SourceType} {SourceId} -- skipping insight extraction", sourceType, sourceId);
            return;
        }

        var prompt = $"""
            Below is a summary of a wellness support {sourceType.ToString().ToLower()}.
            Extract up to 3 meaningful personal insights the user might want to save and revisit.

            An insight should be:
            - A genuine realisation, pattern, or reflection that emerged
            - Written from the user's perspective in first person (e.g. "I tend to...")
            - Concise -- one or two sentences at most
            - Meaningful enough to be worth re-reading later

            Return a JSON array of strings. If there are no clear insights, return an empty array [].
            Do not include explanations -- only the JSON array.

            Summary:
            {summary.Content}
            """;

        var insights = await ExtractInsightsFromAiAsync(prompt);
        if (insights.Count == 0) return;

        // Semantic deduplication — check vector similarity, not just string equality.
        // This catches "I tend to overthink" vs "I notice I overthink things."
        var newInsights = new List<string>();
        foreach (var insight in insights.Where(i => !string.IsNullOrWhiteSpace(i)))
        {
            try
            {
                var isDuplicate = await insightQuery.IsSimilarInsightExistsAsync(userId, insight);
                if (!isDuplicate)
                    newInsights.Add(insight);
                else
                    logger.LogDebug("Skipped semantically similar insight: {Insight}", insight);
            }
            catch
            {
                // If semantic check fails, fall back to exact match
                var exists = await db.SavedInsights.AnyAsync(i =>
                    i.UserId == userId && i.Content.Trim().ToLower() == insight.Trim().ToLower());
                if (!exists)
                    newInsights.Add(insight);
            }
        }

        foreach (var content in newInsights)
        {
            db.SavedInsights.Add(new SavedInsight
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Content = content,
                SourceConversationId = sourceType == SummarySourceType.Conversation ? sourceId : null,
                SourceJournalId = sourceType == SummarySourceType.Journal ? sourceId : null,
                CreatedAt = DateTime.UtcNow
            });
        }

        if (newInsights.Count > 0)
        {
            await db.SaveChangesAsync();
            logger.LogInformation("Extracted {Count} insight(s) from {SourceType} {SourceId}", newInsights.Count, sourceType, sourceId);

            await pushService.SendSilentPushAsync(userId, new Dictionary<string, string> { ["type"] = "insight" });
        }
    }

    private async Task<List<string>> ExtractInsightsFromAiAsync(string prompt)
    {
        try
        {
            var chat = kernel.GetRequiredService<IChatCompletionService>();
            var history = new ChatHistory("You are a concise insight extraction assistant. Respond only with valid JSON.");
            history.AddUserMessage(prompt);
            var result = await chat.GetChatMessageContentAsync(history);

            var json = result.Content?.Trim() ?? "[]";

            if (json.StartsWith("```"))
            {
                var start = json.IndexOf('[');
                var end = json.LastIndexOf(']');
                if (start >= 0 && end > start)
                    json = json[start..(end + 1)];
            }

            return JsonSerializer.Deserialize<List<string>>(json) ?? [];
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to extract insights");
            return [];
        }
    }
}
