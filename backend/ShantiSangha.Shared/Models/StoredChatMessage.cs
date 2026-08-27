namespace ShantiSangha.Shared.Models;

/// One message row from the unified conversation store. Role is "User" or
/// "Assistant" (the stored string). MetadataJson is an opaque blob owned by
/// whichever module wrote the message (e.g. the assistant's reminder ids and
/// photo key) — the store never interprets it.
public record StoredChatMessage(
    Guid Id,
    Guid ConversationId,
    string Role,
    string Content,
    DateTime CreatedAt,
    string? MetadataJson);
