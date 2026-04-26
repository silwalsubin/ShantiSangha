namespace ShantiSangha.Shared.Interfaces;

/// <summary>
/// Cross-module abstraction for "is this user a member of this
/// conversation?" — used by the chat WebSocket endpoint to authorize
/// subscriptions. The current implementation (<c>FriendshipMembershipService</c>
/// in the Friends module) treats each Friendship as a 2-member
/// conversation; a future Group module will plug its own membership
/// source in via composition without touching the WebSocket layer.
/// </summary>
public interface IConversationMembershipService
{
    /// <summary>Return the user IDs that belong to the conversation.
    /// Empty set when the conversation doesn't exist or has no members
    /// the caller can see.</summary>
    Task<HashSet<Guid>> GetMembersAsync(Guid conversationId, CancellationToken ct = default);

    /// <summary>Cheap membership check — should be one query. Used in
    /// the WebSocket auth path so any drift here directly affects
    /// connection latency.</summary>
    Task<bool> IsMemberAsync(Guid conversationId, Guid userId, CancellationToken ct = default);
}
