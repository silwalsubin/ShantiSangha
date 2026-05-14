namespace ShantiSangha.Friends.Models;

public enum FriendMessageSuggestionKind { Reminder }

/// <summary>
/// A one-tap shortcut surfaced in friend chat: the system detected a
/// reminder-shaped statement in a message ("don't forget to call mom
/// on Sunday") and offers to schedule it. One row per (message, user)
/// pair — the detector runs once per message but writes two rows so
/// each participant has independent dismissed / accepted state.
/// </summary>
public class FriendMessageSuggestion
{
    public Guid Id { get; set; }
    public Guid FriendMessageId { get; set; }
    /// <summary>Which user this suggestion is FOR. Both participants in
    /// the conversation get their own row.</summary>
    public Guid UserId { get; set; }
    public FriendMessageSuggestionKind Kind { get; set; }
    public string Label { get; set; } = string.Empty;
    public DateOnly WhenDate { get; set; }
    public string Recurrence { get; set; } = "none";  // "none" | "yearly"
    public DateTime? DismissedAt { get; set; }
    /// <summary>Set once the user has accepted the suggestion and
    /// created a real reminder from it.</summary>
    public Guid? CreatedReminderId { get; set; }
    public DateTime CreatedAt { get; set; }
}
