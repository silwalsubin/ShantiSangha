using Pgvector;

namespace ShantiSangha.Memory.Models;

/// One embedded fragment of the user's own words. The Memory module owns these
/// rows exclusively — source modules (Journal, Chat) never see them; they only
/// publish events that cause chunks to be (re)indexed or purged.
public class MemoryChunk
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    /// "journal" | "chat_message"
    public string SourceType { get; set; } = string.Empty;
    public Guid SourceId { get; set; }

    /// Set for chat_message chunks so retrieval can exclude the conversation
    /// currently in progress.
    public Guid? ConversationId { get; set; }

    public string Content { get; set; } = string.Empty;

    /// SHA-256 of Content — lets re-index skip the embedding call when the
    /// source text hasn't actually changed.
    public string ContentHash { get; set; } = string.Empty;

    public Vector? Embedding { get; set; }

    /// When the user originally wrote this (journal/message CreatedAt).
    public DateTime OccurredAt { get; set; }
    public DateTime IndexedAt { get; set; }
}
