namespace ShantiSangha.Agent.Contracts;

/// A tappable follow-up the assistant offers after a reply. <see cref="Label"/>
/// is the short button text the user sees; <see cref="Prompt"/> is the message
/// sent on tap (it carries the context the short label omits). Ephemeral —
/// generated per turn, never persisted.
public record QuickAction(string Label, string Prompt);
