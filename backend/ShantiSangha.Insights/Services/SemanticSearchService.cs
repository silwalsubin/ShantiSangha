using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Pgvector;
using Pgvector.EntityFrameworkCore;
using ShantiSangha.Insights.Data;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Insights.Services;

public class SemanticSearchService(
    InsightsDbContext db,
    IJournalSearchService journalSearch,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
    ILogger<SemanticSearchService> logger)
{
    public async Task<IReadOnlyList<SemanticSearchResultDto>> SearchInsightsAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default)
    {
        var queryVector = await GetQueryVectorAsync(query, ct);
        if (queryVector is null) return [];

        return await db.SavedInsights
            .Where(i => i.UserId == userId && i.Embedding != null)
            .OrderBy(i => i.Embedding!.L2Distance(queryVector))
            .Take(topK)
            .Select(i => new SemanticSearchResultDto(
                i.Id,
                "insight",
                i.Content,
                (double)i.Embedding!.L2Distance(queryVector),
                i.CreatedAt))
            .ToListAsync(ct);
    }

    public async Task<IReadOnlyList<SemanticSearchResultDto>> SearchJournalsAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default)
    {
        return await journalSearch.SearchAsync(userId, query, topK, ct);
    }

    public async Task<IReadOnlyList<SemanticSearchResultDto>> SearchAllAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default)
    {
        var insightsTask = SearchInsightsAsync(userId, query, topK, ct);
        var journalsTask = SearchJournalsAsync(userId, query, topK, ct);

        await Task.WhenAll(insightsTask, journalsTask);

        return insightsTask.Result
            .Concat(journalsTask.Result)
            .OrderBy(r => r.Distance)
            .Take(topK)
            .ToList();
    }

    public async Task<Vector?> GetQueryVectorAsync(string query, CancellationToken ct = default)
    {
        try
        {
            var result = await embeddingGenerator.GenerateAsync([query], cancellationToken: ct);
            return new Vector(result[0].Vector.ToArray());
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate query embedding for semantic search");
            return null;
        }
    }
}
