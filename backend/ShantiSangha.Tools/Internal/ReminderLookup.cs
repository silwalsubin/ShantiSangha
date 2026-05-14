using ShantiSangha.Reminders.Contracts;

namespace ShantiSangha.Tools.Internal;

internal enum LookupOutcome { None, Single, Ambiguous }

internal record LookupResult(
    LookupOutcome Outcome,
    ReminderResponse? Match,
    IReadOnlyList<ReminderResponse> Candidates);

internal static class ReminderLookup
{
    public static LookupResult FindByLabel(
        IReadOnlyList<ReminderResponse> reminders, string label)
    {
        if (string.IsNullOrWhiteSpace(label) || reminders.Count == 0)
            return new LookupResult(LookupOutcome.None, null, Array.Empty<ReminderResponse>());

        var needle = label.Trim();

        var exact = reminders
            .Where(r => string.Equals(r.Label, needle, StringComparison.OrdinalIgnoreCase))
            .ToList();
        if (exact.Count == 1) return new LookupResult(LookupOutcome.Single, exact[0], exact);
        if (exact.Count > 1) return new LookupResult(LookupOutcome.Ambiguous, null, exact);

        var substring = reminders
            .Where(r => r.Label.Contains(needle, StringComparison.OrdinalIgnoreCase))
            .ToList();
        if (substring.Count == 1) return new LookupResult(LookupOutcome.Single, substring[0], substring);
        if (substring.Count > 1) return new LookupResult(LookupOutcome.Ambiguous, null, substring);

        var tokens = needle.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (tokens.Length == 0)
            return new LookupResult(LookupOutcome.None, null, Array.Empty<ReminderResponse>());

        var token = reminders
            .Where(r => tokens.All(t => r.Label.Contains(t, StringComparison.OrdinalIgnoreCase)))
            .ToList();
        if (token.Count == 1) return new LookupResult(LookupOutcome.Single, token[0], token);
        if (token.Count > 1) return new LookupResult(LookupOutcome.Ambiguous, null, token);

        return new LookupResult(LookupOutcome.None, null, Array.Empty<ReminderResponse>());
    }
}
