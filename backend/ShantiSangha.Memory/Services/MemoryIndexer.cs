using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Logging;
using Pgvector;
using ShantiSangha.Memory.Data;
using ShantiSangha.Memory.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Memory.Services;

/// Writes memory chunks. All source content is pulled through the Shared
/// query-service interfaces — this module never touches another module's
/// tables. Embedding failures are logged and swallowed: memory is best-effort,
/// the source rows are the truth and can always be re-indexed.
public class MemoryIndexer(
    MemoryDbContext db,
    IJournalQueryService journalQuery,
    IChatQueryService chatQuery,
    IEmbeddingGenerator<string, Embedding<float>> embeddingGenerator,
    ILogger<MemoryIndexer> logger)
{
    /// Chat messages shorter than this carry no memory worth keeping
    /// ("ok", "thank you", "good morning").
    private const int MinChatMessageLength = 40;

    public async Task IndexJournalAsync(Guid journalId, CancellationToken ct = default)
    {
        var journal = await journalQuery.GetJournalContentAsync(journalId, ct);
        if (journal is null)
        {
            // Deleted before the job ran — make sure no stale chunk lingers.
            await PurgeSourceAsync("journal", journalId, ct);
            return;
        }

        var text = string.IsNullOrWhiteSpace(journal.Title)
            ? journal.Content
            : $"{journal.Title}\n\n{journal.Content}";

        if (string.IsNullOrWhiteSpace(text)) return;

        await UpsertChunkAsync(
            userId: journal.UserId,
            sourceType: "journal",
            sourceId: journal.Id,
            conversationId: null,
            content: text,
            occurredAt: journal.CreatedAt,
            ct);
    }

    public async Task IndexChatMessagesAsync(Guid userId, Guid[] messageIds, CancellationToken ct = default)
    {
        var messages = await chatQuery.GetMessagesAsync(messageIds, ct);

        foreach (var msg in messages)
        {
            // Only the user's own words become memory — the companion's replies
            // are not the user's life.
            if (!string.Equals(msg.Role, "User", StringComparison.OrdinalIgnoreCase)) continue;

            var content = msg.Content.Trim();
            if (content.Length < MinChatMessageLength) continue;

            await UpsertChunkAsync(
                userId: userId,
                sourceType: "chat_message",
                sourceId: msg.Id,
                conversationId: msg.ConversationId,
                content: content,
                occurredAt: msg.CreatedAt,
                ct);
        }
    }

    public async Task PurgeSourceAsync(string sourceType, Guid sourceId, CancellationToken ct = default)
    {
        await db.MemoryChunks
            .Where(c => c.SourceType == sourceType && c.SourceId == sourceId)
            .ExecuteDeleteAsync(ct);
    }

    public async Task PurgeConversationAsync(Guid conversationId, CancellationToken ct = default)
    {
        await db.MemoryChunks
            .Where(c => c.ConversationId == conversationId)
            .ExecuteDeleteAsync(ct);
    }

    private async Task UpsertChunkAsync(
        Guid userId,
        string sourceType,
        Guid sourceId,
        Guid? conversationId,
        string content,
        DateTime occurredAt,
        CancellationToken ct)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(content)));

        var chunk = await db.MemoryChunks
            .FirstOrDefaultAsync(c => c.SourceType == sourceType && c.SourceId == sourceId, ct);

        if (chunk is not null && chunk.ContentHash == hash) return;

        Vector embedding;
        try
        {
            var result = await embeddingGenerator.GenerateAsync([content], cancellationToken: ct);
            embedding = new Vector(result[0].Vector.ToArray());
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to embed {SourceType} {SourceId}", sourceType, sourceId);
            return;
        }

        if (chunk is null)
        {
            chunk = new MemoryChunk
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                SourceType = sourceType,
                SourceId = sourceId,
                ConversationId = conversationId
            };
            db.MemoryChunks.Add(chunk);
        }

        chunk.Content = content;
        chunk.ContentHash = hash;
        chunk.Embedding = embedding;
        chunk.OccurredAt = occurredAt;
        chunk.IndexedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);
    }
}
