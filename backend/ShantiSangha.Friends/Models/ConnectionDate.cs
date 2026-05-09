namespace ShantiSangha.Friends.Models;

/// A single owner-private "important date" attached to a Connection —
/// birthday, anniversary, the day they met, etc. The list lives on the
/// Connection (overlay) rather than the Person so a viewer's "day we
/// met" doesn't bleed into the friend's view of themselves.
///
/// `Label` is free-form; the iOS layer offers preset suggestions
/// ("Birthday", "Anniversary", "Day we met") but doesn't constrain.
public class ConnectionDate
{
    public Guid Id { get; set; }
    public Guid ConnectionId { get; set; }
    public string Label { get; set; } = string.Empty;
    public DateOnly Date { get; set; }
    public ConnectionDateRecurrence Recurrence { get; set; } = ConnectionDateRecurrence.Yearly;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
