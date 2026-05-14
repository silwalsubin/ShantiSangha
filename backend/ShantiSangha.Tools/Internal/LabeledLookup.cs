namespace ShantiSangha.Tools.Internal;

internal enum LookupOutcome { None, Single, Ambiguous }

internal record LookupResult<T>(
    LookupOutcome Outcome,
    T? Match,
    IReadOnlyList<T> Candidates);

/// <summary>
/// Generic fuzzy-match-by-label for tool inputs. Reminders fuzz on label,
/// connections fuzz on display name — same matching strategy in both
/// places, so it lives once and is parameterized by a label selector.
///
/// Strategy: case-insensitive exact match → substring → all-tokens-match.
/// Returns Single, Ambiguous (with candidates), or None.
/// </summary>
internal static class LabeledLookup
{
    public static LookupResult<T> FindByLabel<T>(
        IReadOnlyList<T> items,
        Func<T, string> labelSelector,
        string label)
    {
        if (string.IsNullOrWhiteSpace(label) || items.Count == 0)
            return new LookupResult<T>(LookupOutcome.None, default, Array.Empty<T>());

        var needle = label.Trim();

        var exact = items
            .Where(i => string.Equals(labelSelector(i), needle, StringComparison.OrdinalIgnoreCase))
            .ToList();
        if (exact.Count == 1) return new LookupResult<T>(LookupOutcome.Single, exact[0], exact);
        if (exact.Count > 1) return new LookupResult<T>(LookupOutcome.Ambiguous, default, exact);

        var substring = items
            .Where(i => labelSelector(i).Contains(needle, StringComparison.OrdinalIgnoreCase))
            .ToList();
        if (substring.Count == 1) return new LookupResult<T>(LookupOutcome.Single, substring[0], substring);
        if (substring.Count > 1) return new LookupResult<T>(LookupOutcome.Ambiguous, default, substring);

        var tokens = needle.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (tokens.Length == 0)
            return new LookupResult<T>(LookupOutcome.None, default, Array.Empty<T>());

        var token = items
            .Where(i =>
            {
                var lbl = labelSelector(i);
                return tokens.All(t => lbl.Contains(t, StringComparison.OrdinalIgnoreCase));
            })
            .ToList();
        if (token.Count == 1) return new LookupResult<T>(LookupOutcome.Single, token[0], token);
        if (token.Count > 1) return new LookupResult<T>(LookupOutcome.Ambiguous, default, token);

        return new LookupResult<T>(LookupOutcome.None, default, Array.Empty<T>());
    }
}
