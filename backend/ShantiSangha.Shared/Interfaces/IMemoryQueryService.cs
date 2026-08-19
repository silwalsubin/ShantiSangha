using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

/// Semantic recall over everything the user has written (journals, voice
/// transcripts via their journal drafts, chat messages). Implemented by the
/// Memory module; consumed by companion surfaces to ground responses in the
/// user's own history.
public interface IMemoryQueryService
{
    /// Returns the most relevant memory fragments for `query`, closest first.
    /// `excludeConversationId` keeps the current conversation's own messages
    /// out of the results — recalling what was just said is noise, not memory.
    Task<IReadOnlyList<MemoryHit>> SearchAsync(
        Guid userId,
        string query,
        int topK = 5,
        Guid? excludeConversationId = null,
        CancellationToken ct = default);
}
