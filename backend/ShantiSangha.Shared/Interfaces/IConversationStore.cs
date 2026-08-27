using ShantiSangha.Shared.Models;

namespace ShantiSangha.Shared.Interfaces;

/// The unified conversation store — one set of tables (owned by the Chat
/// module) holding every AI thread in the app, discriminated by `type`
/// ("general" = the Reflect companion, "assistant" = the Home assistant).
/// Exposed in Shared so the Agent module can persist its turns without a
/// cross-module project reference, following the IChatQueryService pattern.
///
/// Deliberately does NOT publish MessagesSavedEvent: title generation and
/// memory indexing remain the companion pipeline's concern. (Indexing
/// assistant turns would make the agent retrieve its own prior utterances
/// as "memories".)
public interface IConversationStore
{
    Task<Guid> CreateConversationAsync(Guid userId, string type, string? title = null, CancellationToken ct = default);

    Task<IReadOnlyList<ConversationSummary>> ListConversationsAsync(Guid userId, string type, CancellationToken ct = default);

    /// Most recently updated conversation of `type`, or null when none exist.
    Task<Guid?> GetLatestConversationIdAsync(Guid userId, string type, CancellationToken ct = default);

    Task<bool> ConversationBelongsToUserAsync(Guid conversationId, Guid userId, string type, CancellationToken ct = default);

    /// Messages oldest-first; `takeLast` bounds to the most recent N.
    Task<IReadOnlyList<StoredChatMessage>> GetMessagesAsync(Guid conversationId, int? takeLast = null, CancellationToken ct = default);

    /// Appends with a caller-chosen id (callers may need the id before the
    /// row exists, e.g. for feedback attribution) and touches UpdatedAt.
    Task AppendMessageAsync(Guid conversationId, Guid messageId, string role, string content, string? metadataJson = null, CancellationToken ct = default);

    /// Sets the title only when the conversation has none yet.
    Task SetTitleIfEmptyAsync(Guid conversationId, string title, CancellationToken ct = default);

    /// Deletes the conversation and its messages; returns the MetadataJson of
    /// every deleted message so the caller can clean up external resources
    /// (e.g. S3 photo bytes). Returns null when not found / not owned.
    Task<IReadOnlyList<string>?> DeleteConversationAsync(Guid conversationId, Guid userId, CancellationToken ct = default);
}
