using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Pgvector;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Infrastructure.Jobs;

public class GenerateEmbeddingJob(
    AppDbContext db,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
    ILogger<GenerateEmbeddingJob> logger)
{
    public async Task RunForMessageAsync(Guid messageId)
    {
        var message = await db.Messages.FindAsync(messageId);
        if (message is null || message.Embedding is not null) return;

        var embedding = await GetEmbeddingAsync(message.Content);
        if (embedding is null) return;

        message.Embedding = embedding;
        await db.SaveChangesAsync();
        logger.LogDebug("Generated embedding for message {Id}", messageId);
    }

    public async Task RunForJournalAsync(Guid journalId)
    {
        var journal = await db.Journals.FindAsync(journalId);
        if (journal is null || journal.Embedding is not null) return;

        var text = string.IsNullOrWhiteSpace(journal.Title)
            ? journal.Content
            : $"{journal.Title}\n\n{journal.Content}";

        var embedding = await GetEmbeddingAsync(text);
        if (embedding is null) return;

        journal.Embedding = embedding;
        await db.SaveChangesAsync();
        logger.LogDebug("Generated embedding for journal {Id}", journalId);
    }

    public async Task RunForInsightAsync(Guid insightId)
    {
        var insight = await db.SavedInsights.FindAsync(insightId);
        if (insight is null || insight.Embedding is not null) return;

        var embedding = await GetEmbeddingAsync(insight.Content);
        if (embedding is null) return;

        insight.Embedding = embedding;
        await db.SaveChangesAsync();
        logger.LogDebug("Generated embedding for insight {Id}", insightId);
    }

    private async Task<Vector?> GetEmbeddingAsync(string text)
    {
        try
        {
            var result = await embeddingGenerator.GenerateAsync([text]);
            var floats = result[0].Vector.ToArray();
            return new Vector(floats);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate embedding");
            return null;
        }
    }
}
