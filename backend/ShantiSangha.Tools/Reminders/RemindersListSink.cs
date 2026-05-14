namespace ShantiSangha.Tools.Reminders;

/// <summary>
/// Scoped buffer the in-app agent reads after a turn to learn which
/// reminders the assistant referenced via <c>list_reminders</c>. The agent
/// emits these as interactive cards alongside the prose reply.
///
/// Lives in the Tools module so <see cref="RemindersTool"/> can write to
/// it without a dependency on the Agent module. External MCP callers get
/// the same instance per scope but simply never drain it.
/// </summary>
public sealed class RemindersListSink
{
    private readonly List<Guid> _ids = new();

    public void Push(IEnumerable<Guid> ids)
    {
        foreach (var id in ids) _ids.Add(id);
    }

    /// <summary>Returns the unique IDs collected this scope, in first-mention order.</summary>
    public IReadOnlyList<Guid> Drain()
    {
        var seen = new HashSet<Guid>();
        var ordered = new List<Guid>();
        foreach (var id in _ids)
        {
            if (seen.Add(id)) ordered.Add(id);
        }
        _ids.Clear();
        return ordered;
    }
}
