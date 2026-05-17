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
}
