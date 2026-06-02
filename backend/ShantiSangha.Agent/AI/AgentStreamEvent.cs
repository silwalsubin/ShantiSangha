using ShantiSangha.Agent.Contracts;
using ShantiSangha.Reminders.Contracts;

namespace ShantiSangha.Agent.AI;

/// <summary>
/// One frame in the agent's reply stream. Text frames are the LLM's prose;
/// attachment frames carry structured data (e.g. reminders the assistant
/// referenced this turn) so the client can render interactive cards.
/// </summary>
public abstract record AgentStreamEvent
{
    public sealed record Text(string Chunk) : AgentStreamEvent;

    public sealed record Reminders(IReadOnlyList<ReminderResponse> Items) : AgentStreamEvent;

    /// Up to 3 tappable follow-ups offered after the reply. Emitted only when
    /// there's a clearly useful next step; most turns carry none.
    public sealed record QuickActions(IReadOnlyList<QuickAction> Items) : AgentStreamEvent;
}
