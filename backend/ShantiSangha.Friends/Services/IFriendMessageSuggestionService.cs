namespace ShantiSangha.Friends.Services;

public interface IFriendMessageSuggestionService
{
    /// <summary>
    /// Mark the viewer's suggestion for a message as dismissed. Returns
    /// false when no row exists for (messageId, userId) — either the
    /// detector hasn't run yet or the user wasn't a participant.
    /// </summary>
    Task<bool> DismissAsync(Guid userId, Guid messageId, CancellationToken ct = default);

    /// <summary>
    /// Mark the viewer's suggestion as accepted by linking it to a real
    /// reminder they just created from it. Returns false when the row
    /// is missing.
    /// </summary>
    Task<bool> AcceptAsync(Guid userId, Guid messageId, Guid reminderId, CancellationToken ct = default);
}
