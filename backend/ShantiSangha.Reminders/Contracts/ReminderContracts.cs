namespace ShantiSangha.Reminders.Contracts;

public record CreateReminderRequest(
    string Label,
    string Date,
    string? Recurrence = null,
    bool? RemindersEnabled = null,
    Guid? ConnectionId = null,
    Guid[]? CollaboratorUserIds = null);

public record UpdateReminderRequest(
    string? Label = null,
    string? Date = null,
    string? Recurrence = null,
    bool? RemindersEnabled = null,
    bool? Completed = null,
    Guid[]? CollaboratorUserIds = null);

/// One person the owner has shared a reminder with. The owner is NOT in
/// this list — they're identified separately as the reminder's UserId.
public record ReminderCollaboratorDto(
    Guid UserId,
    string DisplayName,
    string? AvatarUrl);

public record ReminderResponse(
    Guid Id,
    string Label,
    DateOnly Date,
    string Recurrence,
    bool RemindersEnabled,
    Guid? ConnectionId,
    DateTime? CompletedAt,
    DateTime CreatedAt,
    int DaysRemaining,
    ReminderCollaboratorDto[] Collaborators,
    /// True when the caller is a collaborator on this reminder, not its
    /// owner. iOS uses this to show "Shared by …" instead of the
    /// owner-only collaborator picker.
    bool IsSharedWithMe,
    /// Owner display name. Surfaced on collaborator views so they know
    /// who shared the reminder. Null on the owner's own rows (they
    /// already know it's theirs).
    string? OwnerDisplayName);
