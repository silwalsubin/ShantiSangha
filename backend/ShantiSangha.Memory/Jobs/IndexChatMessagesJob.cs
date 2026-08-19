using ShantiSangha.Memory.Services;

namespace ShantiSangha.Memory.Jobs;

public class IndexChatMessagesJob(MemoryIndexer indexer)
{
    public Task RunAsync(Guid userId, Guid[] messageIds) => indexer.IndexChatMessagesAsync(userId, messageIds);
}
