using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Pgvector;
using Pgvector.EntityFrameworkCore;
using ShantiSangha.Journal.Data;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Journal.Services;

public class JournalSearchService(
    JournalDbContext db,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
    ILogger<JournalSearchService> logger) : IJournalSearchService
{
    public async Task<IReadOnlyList<SemanticSearchResultDto>> SearchAsync(
        Guid userId, string query, int topK = 5, CancellationToken ct = default)
    {
        var queryVector = await GetQueryVectorAsync(query, ct);
        if (queryVector is null) return [];

        return await db.Journals
            .Where(j => j.UserId == userId && j.Embedding != null)
            .OrderBy(j => j.Embedding!.L2Distance(queryVector))
            .Take(topK)
            .Select(j => new SemanticSearchResultDto(
                j.Id,
                "journal",
                j.Title.Length > 0 ? j.Title : j.Content.Substring(0, Math.Min(j.Content.Length, 120)),
                (double)j.Embedding!.L2Distance(queryVector),
                j.CreatedAt))
            .ToListAsync(ct);
    }

    private async Task<Vector?> GetQueryVectorAsync(string query, CancellationToken ct)
    {
        try
        {
            var result = await embeddingGenerator.GenerateAsync([query], cancellationToken: ct);
            return new Vector(result[0].Vector.ToArray());
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate query embedding for journal search");
            return null;
        }
    }
}
