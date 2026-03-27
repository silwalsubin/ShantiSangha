using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Pgvector;
using Pgvector.EntityFrameworkCore;
using ShantiSangha.Core.Services;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Infrastructure.AI;

public class SemanticSearchService(
    AppDbContext db,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
    ILogger<SemanticSearchService> logger) : ISemanticSearchService
{
    public async Task<IReadOnlyList<SemanticSearchResult>> SearchInsightsAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default)
    {
        var queryVector = await GetQueryVectorAsync(query, ct);
        if (queryVector is null) return [];

        return await db.SavedInsights
            .Where(i => i.UserId == userId && i.Embedding != null)
            .OrderBy(i => i.Embedding!.L2Distance(queryVector))
            .Take(topK)
            .Select(i => new SemanticSearchResult(
                i.Id,
                "insight",
                i.Content,
                (double)i.Embedding!.L2Distance(queryVector),
                i.CreatedAt))
            .ToListAsync(ct);
    }

    public async Task<IReadOnlyList<SemanticSearchResult>> SearchJournalsAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default)
    {
        var queryVector = await GetQueryVectorAsync(query, ct);
        if (queryVector is null) return [];

        return await db.Journals
            .Where(j => j.UserId == userId && j.Embedding != null)
            .OrderBy(j => j.Embedding!.L2Distance(queryVector))
            .Take(topK)
            .Select(j => new SemanticSearchResult(
                j.Id,
                "journal",
                j.Title.Length > 0 ? j.Title : j.Content.Substring(0, Math.Min(j.Content.Length, 120)),
                (double)j.Embedding!.L2Distance(queryVector),
                j.CreatedAt))
            .ToListAsync(ct);
    }

    public async Task<IReadOnlyList<SemanticSearchResult>> SearchAllAsync(
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
