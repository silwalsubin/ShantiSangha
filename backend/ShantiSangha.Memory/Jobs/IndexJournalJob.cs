using ShantiSangha.Memory.Services;

namespace ShantiSangha.Memory.Jobs;

public class IndexJournalJob(MemoryIndexer indexer)
{
    public Task RunAsync(Guid journalId) => indexer.IndexJournalAsync(journalId);
}
