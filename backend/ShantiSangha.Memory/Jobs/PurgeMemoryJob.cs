using ShantiSangha.Memory.Services;

namespace ShantiSangha.Memory.Jobs;

/// Deleting a journal or conversation must also forget its memory — the
/// user's sacred-privacy expectation is that deleted words are gone everywhere.
public class PurgeMemoryJob(MemoryIndexer indexer)
{
    public Task RunForSourceAsync(string sourceType, Guid sourceId)
        => indexer.PurgeSourceAsync(sourceType, sourceId);

    public Task RunForConversationAsync(Guid conversationId)
        => indexer.PurgeConversationAsync(conversationId);
}
