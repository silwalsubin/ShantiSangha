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
}
