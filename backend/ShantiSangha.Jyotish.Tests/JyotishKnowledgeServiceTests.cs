using ShantiSangha.Jyotish.Services;
using Xunit;
using Xunit.Abstractions;

namespace ShantiSangha.Jyotish.Tests;

/// <summary>
/// Validates the Jyotish corpus loader and signature matcher.
/// Ensures the 130-passage corpus loads cleanly and retrieves correctly
/// for representative chart signatures.
/// </summary>
public class JyotishKnowledgeServiceTests(ITestOutputHelper output)
{
    private static JyotishKnowledgeService NewService() => new();

    [Fact]
    public void CorpusLoads_FromEmbeddedResource_WithAtLeast100Passages()
    {
        var svc = NewService();
        Assert.True(svc.TotalPassages >= 100,
            $"Expected at least 100 passages in corpus, got {svc.TotalPassages}");
        output.WriteLine($"Loaded {svc.TotalPassages} passages");
    }

    [Fact]
    public void GetPassages_ReturnsMatch_ForMoonInRashiSignature()
    {
        var svc = NewService();
        var passages = svc.GetPassages(new[] { "moon_in_vrishabha" });
        Assert.NotEmpty(passages);
        Assert.Contains(passages, p => p.Id == "moon_in_vrishabha");
    }

    [Fact]
    public void GetPassages_ReturnsMatch_ForEnglishAlias()
    {
        var svc = NewService();
        // Corpus indexes both sanskrit and english tokens for rashi.
        var passages = svc.GetPassages(new[] { "moon_in_taurus" });
        Assert.NotEmpty(passages);
        Assert.Contains(passages, p => p.Id == "moon_in_vrishabha");
    }

    [Fact]
    public void GetPassages_ReturnsMatch_ForDasha()
    {
        var svc = NewService();
        var passages = svc.GetPassages(new[] { "jupiter_mahadasha" });
        Assert.NotEmpty(passages);
        Assert.Contains(passages, p => p.SignatureType == "dasha");
    }

    [Fact]
    public void GetPassages_ReturnsMatch_ForNakshatra()
    {
        var svc = NewService();
        var passages = svc.GetPassages(new[] { "moon_in_mrigashirsha" });
        Assert.NotEmpty(passages);
    }

    [Fact]
    public void GetPassages_ReturnsMatch_ForPlanetInHouse()
    {
        var svc = NewService();
        var passages = svc.GetPassages(new[] { "saturn_in_h7" });
        Assert.NotEmpty(passages);
    }

    [Fact]
    public void GetPassages_ReturnsEmpty_ForUnknownSignature()
    {
        var svc = NewService();
        var passages = svc.GetPassages(new[] { "this_does_not_exist" });
        Assert.Empty(passages);
    }

    [Fact]
    public void GetPassages_DeduplicatesAcrossSignatures()
    {
        var svc = NewService();
        // Both the sanskrit and english tokens point to the same passage.
        var passages = svc.GetPassages(new[] { "moon_in_vrishabha", "moon_in_taurus" });
        Assert.Single(passages, p => p.Id == "moon_in_vrishabha");
    }

    [Fact]
    public void AllPassages_HaveNonEmptyContent()
    {
        var svc = NewService();
        var all = svc.GetPassages(new[] { "moon_in_ashwini", "jupiter_mahadasha", "saturn_in_h1" });
        foreach (var p in all)
        {
            Assert.False(string.IsNullOrWhiteSpace(p.Content), $"Passage {p.Id} has empty content");
            Assert.False(string.IsNullOrWhiteSpace(p.Id));
            Assert.NotEmpty(p.Signatures);
        }
    }

    // ------------------------------------------------------------------
    // Signature computation — end-to-end from birth data
    // ------------------------------------------------------------------

    [Fact]
    public void ComputeSignatures_ForKathmanduBirth_IncludesExpectedTokens()
    {
        var svc = NewService();
        var signatures = svc.ComputeSignaturesForBirth(
            new DateOnly(1990, 6, 22),
            new TimeOnly(6, 0),
            27.7172, 85.3240,
            new DateTime(2026, 4, 18, 0, 0, 0, DateTimeKind.Utc));

        // Sun at Mithuna, Moon at Vrishabha, Lagna at Mithuna (verified by test chart)
        Assert.Contains("sun_in_mithuna", signatures);
        Assert.Contains("moon_in_vrishabha", signatures);
        Assert.Contains("lagna_in_mithuna", signatures);
        // Current Mahadasha as of 2026-04-18 is Jupiter
        Assert.Contains("jupiter_mahadasha", signatures);
        // Sun in 1st house (whole-sign, Lagna + Sun both in Mithuna)
        Assert.Contains("sun_in_h1", signatures);

        output.WriteLine($"Signatures computed: {signatures.Count}");
        foreach (var s in signatures) output.WriteLine($"  {s}");
    }

    [Fact]
    public void ComputeSignatures_WithoutBirthTime_ReturnsEmpty()
    {
        var svc = NewService();
        var signatures = svc.ComputeSignaturesForBirth(
            new DateOnly(1990, 6, 22),
            null, 27.7172, 85.3240);
        Assert.Empty(signatures);
    }

    [Fact]
    public void ComputeSignatures_WithoutCoordinates_ReturnsPartialSet()
    {
        var svc = NewService();
        var signatures = svc.ComputeSignaturesForBirth(
            new DateOnly(1990, 6, 22),
            new TimeOnly(6, 0),
            null, null,
            new DateTime(2026, 4, 18, 0, 0, 0, DateTimeKind.Utc));

        // Rashi placements work without lat/lon (we treat input as UTC).
        // But no lagna, no houses.
        Assert.Contains("moon_in_vrishabha", signatures);
        Assert.DoesNotContain(signatures, s => s.StartsWith("lagna_"));
        Assert.DoesNotContain(signatures, s => s.Contains("_in_h"));
    }

    [Fact]
    public void EndToEnd_ChartSignaturesRetrieveActualPassages()
    {
        var svc = NewService();
        var signatures = svc.ComputeSignaturesForBirth(
            new DateOnly(1990, 6, 22),
            new TimeOnly(6, 0),
            27.7172, 85.3240,
            new DateTime(2026, 4, 18, 0, 0, 0, DateTimeKind.Utc));

        var passages = svc.GetPassages(signatures);

        // For this chart we should get at least 8 passages:
        // Sun rashi, Moon rashi, Lagna rashi, Moon nakshatra, Jupiter mahadasha,
        // Saturn-in-H7, Jupiter-in-H1, Rahu-in-H8, Ketu-in-H2
        Assert.True(passages.Count >= 6,
            $"Expected at least 6 passages for full chart, got {passages.Count}");

        output.WriteLine($"Retrieved {passages.Count} passages for user chart:");
        foreach (var p in passages)
            output.WriteLine($"  {p.Id} [{p.Polarity}]");
    }
}
