using System.Text.RegularExpressions;

namespace ShantiSangha.Friends.Detection;

/// <summary>
/// Stage 1 of the reminder-suggestion detector. Cheap regex pass that
/// answers "is this message worth running an LLM on?" Most chit-chat
/// stops here; the LLM never sees it.
///
/// The signal is co-occurrence — a date token AND a reminder verb /
/// cue both appearing within a short word-distance of each other.
/// Either one alone is too noisy ("Friday's my favorite day" / "I
/// need this") so we require both.
/// </summary>
internal static class RegexPreFilter
{
    private const int MaxWordsBetween = 12;

    private static readonly Regex DateToken = BuildDateRegex();
    private static readonly Regex ReminderCue = BuildCueRegex();

    public static bool LooksReminderShaped(string? body)
    {
        if (string.IsNullOrWhiteSpace(body)) return false;
        if (body.Length > 4000) return false;

        var dateMatches = DateToken.Matches(body);
        if (dateMatches.Count == 0) return false;

        var cueMatches = ReminderCue.Matches(body);
        if (cueMatches.Count == 0) return false;

        // Require any date and any cue to land within ~12 words of
        // each other. Prevents "I had a meeting yesterday" + "remind
        // me to grab milk" from cross-matching as one signal when
        // they're in different sentences far apart.
        foreach (Match d in dateMatches)
        {
            foreach (Match c in cueMatches)
            {
                if (WordDistance(body, d, c) <= MaxWordsBetween) return true;
            }
        }
        return false;
    }

    private static int WordDistance(string body, Match a, Match b)
    {
        var (left, right) = a.Index < b.Index ? (a, b) : (b, a);
        var between = body.AsSpan(left.Index + left.Length,
            right.Index - (left.Index + left.Length));
        var count = 0;
        var inWord = false;
        foreach (var ch in between)
        {
            if (char.IsWhiteSpace(ch))
            {
                if (inWord) { count++; inWord = false; }
            }
            else
            {
                inWord = true;
            }
        }
        if (inWord) count++;
        return count;
    }

    private static Regex BuildDateRegex()
    {
        // Day-of-week, month names, common relative phrases, "in N
        // days/weeks", and explicit numeric dates (M/D, M-D, M.D, with
        // optional year).
        var pattern = @"\b("
            + @"today|tonight|tomorrow|yesterday|"
            + @"monday|tuesday|wednesday|thursday|friday|saturday|sunday|"
            + @"mon|tue|tues|wed|thu|thurs|fri|sat|sun|"
            + @"january|february|march|april|may|june|july|august|september|october|november|december|"
            + @"jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec|"
            + @"next\s+(?:week|month|year|monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)|"
            + @"this\s+(?:week|month|weekend|year|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|"
            + @"in\s+\d+\s+(?:day|days|week|weeks|month|months|year|years)|"
            + @"\d{1,2}[/.\-]\d{1,2}(?:[/.\-]\d{2,4})?"
            + @")\b";
        return new Regex(pattern, RegexOptions.IgnoreCase | RegexOptions.Compiled);
    }

    private static Regex BuildCueRegex()
    {
        // Cues are a generous net — false positives only cost the LLM
        // call, and stage 2 downgrades them to "low" confidence. Past
        // tense ("I had a meeting yesterday") is left to the LLM.
        var pattern = @"\b("
            + @"remind\s+me|don'?t\s+forget|do\s+not\s+forget|"
            + @"remember\s+to|need\s+to|have\s+to|"
            + @"make\s+sure|gotta|got\s+to|"
            + @"let'?s\s+|"
            + @"meet|pick\s+up|drop\s+by|swing\s+by|"
            + @"by\s+|before\s+|"
            + @"due\s+|deadline|"
            + @"appointment|meeting|call|"
            + @"birthday|anniversary"
            + @")";
        return new Regex(pattern, RegexOptions.IgnoreCase | RegexOptions.Compiled);
    }
}
