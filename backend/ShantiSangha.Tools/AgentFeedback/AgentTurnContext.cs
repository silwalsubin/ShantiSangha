namespace ShantiSangha.Tools.AgentFeedback;

/// <summary>
/// Per-request mutable bag of "facts about the current turn" the orchestrator
/// stashes for tools to read. Right now it only carries the id of the user
/// AgentMessage that triggered this turn, so the feedback tool can link
/// entries back to the exact exchange that produced them.
///
/// Scoped service — fresh instance per HTTP request.
/// </summary>
public class AgentTurnContext
{
    public Guid? CurrentUserMessageId { get; set; }

    /// When set, this turn is scoped to one reminder (the "Plan with
    /// assistant" surface). Tools like update_reminder_notes target this
    /// reminder directly instead of fuzzy-matching a label.
    public Guid? ScopedReminderId { get; set; }
}
