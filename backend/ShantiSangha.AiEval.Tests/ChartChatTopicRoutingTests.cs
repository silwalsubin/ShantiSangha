using System.Text.Json;
using System.Text.Json.Serialization;
using ShantiSangha.Chat.AI;
using ShantiSangha.Shared.Jyotish;
using Xunit;

namespace ShantiSangha.AiEval.Tests;

/// <summary>
/// Regression suite for chart-chat topic routing. Loads a golden-set JSON of
/// representative user questions, runs each through ChartTopicRouter.Rerank
/// against a synthetic passage pool that covers every (planet × house), and
/// asserts the expected signature families land in the top-K.
///
/// This test is intentionally DB-free: it exercises the rerank scoring in
/// isolation, so CI can run it on every PR without Postgres/pgvector. If the
/// keyword map in ChartTopicRouter regresses — a rule deleted, a keyword
/// renamed, a topic silently shifting houses — these cases fail loudly.
///
/// To extend: add a case to GoldenSets/chart_chat_topic_routing.json. See
/// the "$how_to_add_a_case" note in that file for the recipe. LLM-as-judge
/// generation tests belong in a separate file (gated on env flag) — this
/// file is the deterministic half.
/// </summary>
public class ChartChatTopicRoutingTests
{
    public static IEnumerable<object[]> Cases()
    {
        var json = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory, "GoldenSets", "chart_chat_topic_routing.json"));
        var set = JsonSerializer.Deserialize<GoldenSet>(json, SerializerOpts)
            ?? throw new InvalidOperationException("Failed to parse golden set");
        foreach (var c in set.Cases)
            yield return new object[] { c };
    }

    [Theory]
    [MemberData(nameof(Cases))]
    public void Rerank_lands_expected_signature_families_in_top_k(GoldenCase testCase)
    {
        var pool = BuildSyntheticPassagePool();
        var reranked = ChartTopicRouter.Rerank(testCase.Query, pool);

        // Empty expected-prefix list is a "no-topic-matches" case: we don't
        // assert on the top-K, only that Rerank didn't explode on input.
        if (testCase.ExpectedTopSignaturePrefix.Count == 0)
        {
            Assert.NotNull(reranked);
            return;
        }

        var topK = reranked.Take(testCase.TopK).ToList();

        foreach (var prefix in testCase.ExpectedTopSignaturePrefix)
        {
            var hit = topK.Any(p => p.Signatures.Any(s =>
                s.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)));

            Assert.True(hit,
                $"[{testCase.Id}] Expected a passage with signature starting '{prefix}' " +
                $"in top {testCase.TopK} for query \"{testCase.Query}\". " +
                $"Got: [{string.Join(", ", topK.Select(p => p.Signatures.FirstOrDefault() ?? "?"))}]. " +
                $"Notes: {testCase.Notes}");
        }
    }

    /// <summary>
    /// Builds a synthetic passage pool spanning every (planet × house), plus
    /// a few topic-agnostic passages (lagna-in-sign, conjunctions) so rerank
    /// has realistic alternatives to sort through. Each passage carries a
    /// single signature so scoring is unambiguous in the test harness.
    /// </summary>
    private static IReadOnlyList<JyotishPassage> BuildSyntheticPassagePool()
    {
        var planets = new[] { "sun", "moon", "mars", "mercury", "jupiter", "venus", "saturn", "rahu", "ketu" };
        var pool = new List<JyotishPassage>();

        foreach (var planet in planets)
        {
            for (var h = 1; h <= 12; h++)
            {
                var sig = $"{planet}_in_h{h}";
                pool.Add(new JyotishPassage
                {
                    Id = sig,
                    Signatures = [sig],
                    Title = sig,
                    Content = $"Synthetic passage for {sig}",
                    Source = "golden-set-mock",
                    Polarity = "mixed",
                    Scope = "lifetime"
                });
            }
        }

        // A handful of non-planet-prefixed signatures that should NEVER outrank
        // planet-in-house passages when a topic rule fires.
        string[] decoys =
        [
            "lagna_in_mesha",
            "lagna_in_karka",
            "conj_sun_mercury",
            "conj_jupiter_venus",
            "manglik",
            "saturn_mahadasha",
        ];
        foreach (var sig in decoys)
        {
            pool.Add(new JyotishPassage
            {
                Id = sig,
                Signatures = [sig],
                Title = sig,
                Content = $"Synthetic decoy for {sig}",
                Source = "golden-set-mock",
                Polarity = "mixed",
                Scope = "lifetime"
            });
        }

        return pool;
    }

    private static readonly JsonSerializerOptions SerializerOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true,
    };

    public record GoldenSet(
        [property: JsonPropertyName("cases")] List<GoldenCase> Cases);

    public record GoldenCase(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("query")] string Query,
        [property: JsonPropertyName("top_k")] int TopK,
        [property: JsonPropertyName("expected_top_signature_prefix")] List<string> ExpectedTopSignaturePrefix,
        [property: JsonPropertyName("notes")] string? Notes = null)
    {
        public override string ToString() => $"{Id}: {Query}";
    }
}
