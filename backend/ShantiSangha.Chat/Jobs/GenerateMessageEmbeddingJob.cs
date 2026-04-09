using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Pgvector;
using ShantiSangha.Chat.Data;

namespace ShantiSangha.Chat.Jobs;

public class GenerateMessageEmbeddingJob(
    ChatDbContext db,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
    ILogger<GenerateMessageEmbeddingJob> logger)
{
    public async Task RunAsync(Guid messageId)
    {
        var message = await db.Messages.FindAsync(messageId);
        if (message is null || message.Embedding is not null) return;

        try
        {
            var result = await embeddingGenerator.GenerateAsync([message.Content]);
            var floats = result[0].Vector.ToArray();
            message.Embedding = new Vector(floats);
            await db.SaveChangesAsync();
            logger.LogDebug("Generated embedding for message {Id}", messageId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to generate embedding for message {Id}", messageId);
        }
    }
}
