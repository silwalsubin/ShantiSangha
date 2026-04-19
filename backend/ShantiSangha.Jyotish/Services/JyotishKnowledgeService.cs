using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.AI;
using Pgvector;
using Pgvector.EntityFrameworkCore;
using ShantiSangha.Jyotish.Data;
using ShantiSangha.Jyotish.Models;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Jyotish.Services;

/// <summary>
/// Postgres-backed Jyotish corpus, with pgvector for semantic retrieval.
/// Exact-match signature lookup uses the GIN-indexed signatures[] column;
/// thematic queries use L2 distance on the 1536-dim embedding.
/// </summary>
public class JyotishKnowledgeService(
    JyotishDbContext db,
    IEmbeddingGenerator<string, Embedding<float>> embedder) : IJyotishKnowledgeService
{
    public async Task<IReadOnlyList<JyotishPassage>> GetPassagesAsync(
        IEnumerable<string> signatures,
        CancellationToken ct = default)
    {
        var normalized = signatures
            .Select(Normalize)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct()
            .ToArray();

        if (normalized.Length == 0) return Array.Empty<JyotishPassage>();

        // Postgres array overlap — matches any row whose signatures[] intersects input.
        var entities = await db.Passages
            .Where(p => p.Signatures.Any(s => normalized.Contains(s)))
            .AsNoTracking()
            .ToListAsync(ct);

        return entities.Select(ToDto).ToList();
    }

    public async Task<IReadOnlyList<JyotishPassage>> SearchSemanticAsync(
        string query,
        string? signatureType = null,
        int topK = 10,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(query)) return Array.Empty<JyotishPassage>();

        var queryVector = await GenerateEmbeddingAsync(query, ct);
        if (queryVector is null) return Array.Empty<JyotishPassage>();

        var q = db.Passages.Where(p => p.Embedding != null);
        if (!string.IsNullOrWhiteSpace(signatureType))
        {
            var st = signatureType.Trim();
            q = q.Where(p => p.SignatureType == st);
        }

        var entities = await q
            .OrderBy(p => p.Embedding!.L2Distance(queryVector))
            .Take(topK)
            .AsNoTracking()
            .ToListAsync(ct);

        return entities.Select(ToDto).ToList();
    }

    public Task<int> CountAsync(CancellationToken ct = default)
        => db.Passages.CountAsync(ct);

    public IReadOnlyList<string> ComputeSignaturesForBirth(
        DateOnly birthDate,
        TimeOnly? birthTime,
        double? latitude,
        double? longitude,
        DateTime? now = null)
        => ChartSignatures.ComputeNatalSignatures(birthDate, birthTime, latitude, longitude, now);

    /// <summary>
    /// Generates the 1536-dim embedding for the text used to index a passage.
    /// Internal helper exposed for the ingestion endpoint to reuse.
    /// </summary>
    public async Task<Vector?> GenerateEmbeddingAsync(string text, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var result = await embedder.GenerateAsync([text], cancellationToken: ct);
        if (result.Count == 0) return null;
        var floats = result[0].Vector.ToArray();
        return new Vector(floats);
    }

    private static string Normalize(string s) => s?.Trim().ToLowerInvariant() ?? string.Empty;

    private static JyotishPassage ToDto(JyotishPassageEntity e) => new()
    {
        Id = e.PassageId,
        SignatureType = e.SignatureType,
        Signatures = e.Signatures,
        Title = e.Title,
        Content = e.Content,
        Themes = e.Themes,
        Polarity = e.Polarity,
        Source = e.Source,
        Scope = e.Scope,
    };
}
