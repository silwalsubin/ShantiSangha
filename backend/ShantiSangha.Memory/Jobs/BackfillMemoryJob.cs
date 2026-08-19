using Microsoft.Extensions.Logging;
using ShantiSangha.Memory.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Memory.Jobs;

/// One-time (but idempotent) sweep that indexes everything written before the
/// Memory module existed. Enqueued on every boot: already-indexed content is
/// skipped by the content-hash check, so a clean run costs a few row lookups
/// and zero embedding calls.
public class BackfillMemoryJob(
    MemoryIndexer indexer,
    IJournalQueryService journalQuery,
    IChatQueryService chatQuery,
    ILogger<BackfillMemoryJob> logger)
{
    private const int MinChatMessageLength = 40;

    public async Task RunAsync()
    {
        var journalIds = await journalQuery.GetAllJournalIdsAsync();
        foreach (var id in journalIds)
            await indexer.IndexJournalAsync(id);

        var refs = await chatQuery.GetAllUserMessageRefsAsync(MinChatMessageLength);
        foreach (var group in refs.GroupBy(r => r.UserId))
            await indexer.IndexChatMessagesAsync(group.Key, group.Select(r => r.MessageId).ToArray());

        logger.LogInformation(
            "Memory backfill swept {JournalCount} journals and {MessageCount} chat messages",
            journalIds.Count, refs.Count);
    }
}
