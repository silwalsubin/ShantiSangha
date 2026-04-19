using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Chat.AI;

/// <summary>
/// Maps a user's chart question to the chart signatures classical Jyotish
/// traditionally reads for that topic. Used to rerank signature-matched
/// passages so the most relevant ones end up at the top of the prompt.
///
/// This is intentionally a keyword map, not an LLM classifier — keeping topic
/// → house/planet routing deterministic prevents the LLM from drifting to
/// whatever happens to feel relevant. Expand the table as we learn which
/// question shapes users actually ask.
/// </summary>
internal static class ChartTopicRouter
{
    /// <summary>
    /// Topic groups with the chart house numbers + planet names classically
    /// consulted for that area of life. Each entry's `Houses` and `Planets`
    /// contribute to passage-relevance scoring when any `Keywords` appear in
    /// the user's message.
    /// </summary>
    private static readonly TopicRule[] Rules =
    [
        new TopicRule(
            Keywords: ["wealth", "money", "rich", "invest", "finance", "income", "earning", "stocks", "savings"],
            Houses: [2, 11],
            Planets: ["jupiter", "venus", "mercury"]),

        new TopicRule(
            Keywords: ["career", "work", "job", "profession", "business", "promotion", "boss"],
            Houses: [10, 6],
            Planets: ["sun", "saturn", "mercury"]),

        new TopicRule(
            Keywords: ["marriage", "partner", "partnership", "spouse", "relationship", "love life", "dating"],
            Houses: [7, 5],
            Planets: ["venus", "jupiter"]),

        new TopicRule(
            Keywords: ["love", "romance", "passion", "attraction", "desire"],
            Houses: [5, 7],
            Planets: ["venus", "moon"]),

        new TopicRule(
            Keywords: ["children", "child", "kid", "creativity", "creative", "artistic", "art"],
            Houses: [5],
            Planets: ["jupiter", "venus", "moon"]),

        new TopicRule(
            Keywords: ["health", "body", "illness", "disease", "fitness", "physical"],
            Houses: [1, 6, 8],
            Planets: ["sun", "mars", "saturn"]),

        new TopicRule(
            Keywords: ["home", "family", "mother", "house", "dwelling", "roots"],
            Houses: [4],
            Planets: ["moon"]),

        new TopicRule(
            Keywords: ["father", "dharma", "faith", "religion", "spiritual", "teacher", "guru", "pilgrimage"],
            Houses: [9],
            Planets: ["jupiter", "sun"]),

        new TopicRule(
            Keywords: ["siblings", "brother", "sister", "courage", "effort", "initiative"],
            Houses: [3],
            Planets: ["mars", "mercury"]),

        new TopicRule(
            Keywords: ["education", "study", "learning", "knowledge", "intellect", "mind"],
            Houses: [4, 5],
            Planets: ["mercury", "jupiter"]),

        new TopicRule(
            Keywords: ["travel", "abroad", "foreign", "move", "relocation"],
            Houses: [3, 9, 12],
            Planets: ["mars", "mercury", "rahu"]),

        new TopicRule(
            Keywords: ["transformation", "change", "crisis", "loss", "inheritance", "secret", "occult"],
            Houses: [8],
            Planets: ["saturn", "mars", "ketu"]),

        new TopicRule(
            Keywords: ["spirituality", "moksha", "liberation", "solitude", "retreat", "sleep", "dreams"],
            Houses: [12, 9],
            Planets: ["jupiter", "ketu"]),

        new TopicRule(
            Keywords: ["personality", "self", "who am i", "identity", "my nature"],
            Houses: [1],
            Planets: ["moon", "sun"]),
    ];

    /// <summary>
    /// Returns the passages reordered by topical relevance to the message.
    /// Passages that match an active topic's houses/planets come first;
    /// untouched passages preserve their original relative order after.
    /// </summary>
    public static IReadOnlyList<JyotishPassage> Rerank(
        string message,
        IReadOnlyList<JyotishPassage> passages)
    {
        if (passages.Count == 0) return passages;
        var lower = message.ToLowerInvariant();

        var activeHouses = new HashSet<int>();
        var activePlanets = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rule in Rules)
        {
            if (rule.Keywords.Any(k => lower.Contains(k)))
            {
                foreach (var h in rule.Houses) activeHouses.Add(h);
                foreach (var p in rule.Planets) activePlanets.Add(p);
            }
        }

        if (activeHouses.Count == 0 && activePlanets.Count == 0) return passages;

        // Stable-sort by score descending, preserving original order for ties.
        return passages
            .Select((p, i) => (Passage: p, OriginalIndex: i, Score: Score(p, activeHouses, activePlanets)))
            .OrderByDescending(x => x.Score)
            .ThenBy(x => x.OriginalIndex)
            .Select(x => x.Passage)
            .ToList();
    }

    private static int Score(JyotishPassage p, HashSet<int> activeHouses, HashSet<string> activePlanets)
    {
        int score = 0;
        foreach (var sig in p.Signatures)
        {
            var s = sig.ToLowerInvariant();
            // Planet signatures start with the planet name (e.g. "mars_in_h7").
            foreach (var planet in activePlanets)
            {
                if (s.StartsWith(planet + "_", StringComparison.Ordinal))
                {
                    score += 2;
                    break;
                }
            }
            // House signatures contain "_h{N}_" or end with "_h{N}".
            foreach (var h in activeHouses)
            {
                var houseToken = $"_h{h}";
                if (s.Contains(houseToken, StringComparison.Ordinal))
                {
                    score += 3;
                    break;
                }
            }
        }
        return score;
    }

    private record TopicRule(string[] Keywords, int[] Houses, string[] Planets);
}
