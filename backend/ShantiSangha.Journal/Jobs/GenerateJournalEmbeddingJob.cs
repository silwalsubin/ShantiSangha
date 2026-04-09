using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Pgvector;
using ShantiSangha.Journal.Data;

namespace ShantiSangha.Journal.Jobs;

public class GenerateJournalEmbeddingJob(
    JournalDbContext db,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
    ILogger<GenerateJournalEmbeddingJob> logger)
{
    public async Task RunForJournalAsync(Guid journalId)
    {
        var journal = await db.Journals.FindAsync(journalId);
        if (journal is null || journal.Embedding is not null) return;

        var text = string.IsNullOrWhiteSpace(journal.Title)
            ? journal.Content
            : $"{journal.Title}\n\n{journal.Content}";

        try
        {
            var result = await embeddingGenerator.GenerateAsync([text]);
            var floats = result[0].Vector.ToArray();
            journal.Embedding = new Vector(floats);
            await db.SaveChangesAsync();
            logger.LogDebug("Generated embedding for journal {Id}", journalId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate embedding for journal {Id}", journalId);
        }
    }
}
