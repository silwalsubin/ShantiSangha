using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.AI;
using Pgvector;
using Pgvector.EntityFrameworkCore;
using ShantiSangha.Memory.Data;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Memory.Services;

public class MemoryQueryService(
    MemoryDbContext db,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator) : IMemoryQueryService
{
    /// L2 distance on unit-normalized OpenAI embeddings: 1.30 ≈ cosine 0.15.
    /// Loose on purpose — mild relevance still helps the companion feel like it
    /// remembers; only true junk is cut.
    private const double MaxDistance = 1.30;

    public async Task<IReadOnlyList<MemoryHit>> SearchAsync(
        Guid userId,
        string query,
        int topK = 5,
        Guid? excludeConversationId = null,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(query)) return [];

        var result = await embeddingGenerator.GenerateAsync([query], cancellationToken: ct);
        var queryVector = new Vector(result[0].Vector.ToArray());

        var hits = await db.MemoryChunks
            .Where(c => c.UserId == userId && c.Embedding != null)
            .Where(c => excludeConversationId == null || c.ConversationId != excludeConversationId)
            .OrderBy(c => c.Embedding!.L2Distance(queryVector))
            .Take(topK)
            .Select(c => new MemoryHit(
                c.SourceType,
                c.SourceId,
                c.Content,
                c.OccurredAt,
                c.Embedding!.L2Distance(queryVector)))
            .ToListAsync(ct);

        return hits.Where(h => h.Distance <= MaxDistance).ToList();
    }

    public async Task<IReadOnlyList<MemoryHit>> GetRecentAsync(
        Guid userId,
        int count = 5,
        CancellationToken ct = default)
    {
        return await db.MemoryChunks
            .Where(c => c.UserId == userId && c.Embedding != null)
            .OrderByDescending(c => c.OccurredAt)
            .Take(count)
            .Select(c => new MemoryHit(c.SourceType, c.SourceId, c.Content, c.OccurredAt, 0d))
            .ToListAsync(ct);
    }
}
