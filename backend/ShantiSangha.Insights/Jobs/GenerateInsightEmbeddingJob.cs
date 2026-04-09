using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Pgvector;
using ShantiSangha.Insights.Data;

namespace ShantiSangha.Insights.Jobs;

public class GenerateInsightEmbeddingJob(
    InsightsDbContext db,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
    ILogger<GenerateInsightEmbeddingJob> logger)
{
    public async Task RunAsync(Guid insightId)
    {
        var insight = await db.SavedInsights.FindAsync(insightId);
        if (insight is null || insight.Embedding is not null) return;

        try
        {
            var result = await embeddingGenerator.GenerateAsync([insight.Content]);
            var floats = result[0].Vector.ToArray();
            insight.Embedding = new Vector(floats);
            await db.SaveChangesAsync();
            logger.LogDebug("Generated embedding for insight {Id}", insightId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate embedding for insight {Id}", insightId);
        }
    }
}
