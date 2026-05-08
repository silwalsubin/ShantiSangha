using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Jyotish.Data;
using ShantiSangha.Jyotish.Models;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Jyotish.Services;

// Implements IPairChartReadingService (Shared). Interface in Shared so
// Friends can invalidate on share revocation without referencing Jyotish.

/// <summary>
/// Composes the viewer's private reading of a specific subject's chart.
/// Each of the 4 sections runs an independent LLM call composed from both
/// charts plus pre-computed cross-chart facts (the subject's planets placed
/// in the viewer's house system) plus existing solo passages keyed off
/// either chart's signatures. v1 ships without new corpus or new signature
/// types — synastry is composed by the LLM from chart facts and the
/// pre-existing solo passage substrate.
/// </summary>
public class PairChartReadingService(
    JyotishDbContext db,
    IJyotishContextService jyotishContext,
    IJyotishKnowledgeService knowledge,
    [FromKeyedServices(AiModels.SmartServiceId)] IChatCompletionService chat,
    ILogger<PairChartReadingService> logger) : IPairChartReadingService
{
    /// <summary>
    /// Bump whenever the prompt, section set, cross-chart facts, or composition
    /// rules change materially. The hash includes this constant so every
    /// cached pair reading invalidates and regenerates on next view.
    /// </summary>
    private const string PairReadingVersion = "v1-2026-05-07-initial";

    public async Task<PairChartReading?> GetAsync(Guid viewerUserId, Guid subjectUserId, CancellationToken ct = default)
    {
        var row = await db.PairReadings.AsNoTracking().FirstOrDefaultAsync(
            r => r.ViewerUserId == viewerUserId && r.SubjectUserId == subjectUserId, ct);
        if (row is null) return null;

        var viewerCtx = await jyotishContext.GetContextAsync(viewerUserId, DateOnly.FromDateTime(DateTime.UtcNow), ct);
        var subjectCtx = await jyotishContext.GetContextAsync(subjectUserId, DateOnly.FromDateTime(DateTime.UtcNow), ct);
        var currentHash = ComputeHash(viewerCtx, subjectCtx);
        if (currentHash != row.ChartHashPair) return null;

        var sections = Deserialize(row.SectionsJson);
        return new PairChartReading(sections, row.GeneratedAt);
    }

    public async Task<PairChartReading> GenerateAsync(Guid viewerUserId, Guid subjectUserId, CancellationToken ct = default)
    {
        var viewerCtx = await jyotishContext.GetContextAsync(viewerUserId, DateOnly.FromDateTime(DateTime.UtcNow), ct);
        var subjectCtx = await jyotishContext.GetContextAsync(subjectUserId, DateOnly.FromDateTime(DateTime.UtcNow), ct);

        if (viewerCtx?.Chart is null || subjectCtx?.Chart is null)
            throw new InvalidOperationException("both viewer and subject must have complete birth details on file");

        var hash = ComputeHash(viewerCtx, subjectCtx);
        var crossFacts = ComputeCrossChartFacts(viewerCtx.Chart, subjectCtx.Chart);

        // Combine signatures from both charts so passage retrieval covers both
        // sides. Solo passages for either chart's placements are fair game as
        // raw material — the LLM weaves the synastry reading on top.
        var allSignatures = viewerCtx.DeriveSignatures()
            .Concat(subjectCtx.DeriveSignatures())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        var sectionTasks = PairReadingSection.All
            .Select(section => ComposeSectionSafeAsync(
                section, viewerCtx, subjectCtx, crossFacts, allSignatures, viewerUserId, subjectUserId, ct))
            .ToArray();
        var results = await Task.WhenAll(sectionTasks);

        var sections = new Dictionary<string, string>();
        var usage = new Dictionary<string, string[]>();
        var failed = new List<string>();
        foreach (var (section, prose, passageIds, didFail) in results)
        {
            sections[section] = prose;
            usage[section] = passageIds;
            if (didFail) failed.Add(section);
        }

        if (failed.Count > 0)
        {
            logger.LogWarning(
                "Pair reading viewer={Viewer} subject={Subject} had {Failed} failed sections: {Sections}",
                viewerUserId, subjectUserId, failed.Count, string.Join(", ", failed));
        }

        var row = await UpsertAsync(viewerUserId, subjectUserId, hash, sections, usage, ct);
        return new PairChartReading(sections, row.GeneratedAt);
    }

    public async Task InvalidateAsync(Guid viewerUserId, Guid subjectUserId, CancellationToken ct = default)
    {
        await db.PairReadings
            .Where(r => r.ViewerUserId == viewerUserId && r.SubjectUserId == subjectUserId)
            .ExecuteDeleteAsync(ct);
    }

    // --- Section composition ---------------------------------------------

    private async Task<(string Section, string Prose, string[] PassageIds, bool Failed)> ComposeSectionSafeAsync(
        string section,
        JyotishContext viewer,
        JyotishContext subject,
        CrossChartFacts crossFacts,
        IReadOnlyList<string> allSignatures,
        Guid viewerUserId,
        Guid subjectUserId,
        CancellationToken ct)
    {
        const int MaxAttempts = 3;
        for (int attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            try
            {
                var (prose, passageIds) = await ComposeSectionAsync(section, viewer, subject, crossFacts, allSignatures, ct);
                if (!string.IsNullOrWhiteSpace(prose)) return (section, prose, passageIds, false);
                logger.LogWarning(
                    "Pair section '{Section}' empty on attempt {Attempt} for viewer={Viewer} subject={Subject}",
                    section, attempt, viewerUserId, subjectUserId);
            }
            catch (Exception ex) when (attempt < MaxAttempts)
            {
                logger.LogWarning(ex,
                    "Pair section '{Section}' threw on attempt {Attempt} — retrying", section, attempt);
            }
            catch (Exception ex)
            {
                logger.LogError(ex,
                    "Pair section '{Section}' failed after {Attempts} attempts viewer={Viewer} subject={Subject}",
                    section, MaxAttempts, viewerUserId, subjectUserId);
                return (section, string.Empty, Array.Empty<string>(), true);
            }
            if (attempt < MaxAttempts)
                await Task.Delay(TimeSpan.FromMilliseconds(500 * attempt), ct);
        }
        return (section, string.Empty, Array.Empty<string>(), true);
    }

    private async Task<(string Prose, string[] PassageIds)> ComposeSectionAsync(
        string section,
        JyotishContext viewer,
        JyotishContext subject,
        CrossChartFacts crossFacts,
        IReadOnlyList<string> allSignatures,
        CancellationToken ct)
    {
        // Pull every passage the combined signature set hits. Pair sections
        // intentionally don't filter by planet the way solo sections do —
        // the synastry reading benefits from access to both charts' depth.
        var passages = allSignatures.Count == 0
            ? Array.Empty<JyotishPassage>()
            : await knowledge.GetPassagesAsync(allSignatures, ct);
        var passageIds = passages.Select(p => p.Id).ToArray();

        var systemPrompt = BuildSectionPrompt(section, viewer, subject, crossFacts, passages);

        var history = new ChatHistory();
        history.AddSystemMessage(systemPrompt);
        history.AddUserMessage($"Compose the '{section}' section now.");

        var result = await chat.GetChatMessageContentAsync(history, cancellationToken: ct);
        var prose = (result.Content ?? string.Empty).Trim();
        return (prose, passageIds);
    }

    private static string BuildSectionPrompt(
        string section,
        JyotishContext viewer,
        JyotishContext subject,
        CrossChartFacts crossFacts,
        IReadOnlyList<JyotishPassage> passages)
    {
        // Stable preamble first (cache-friendly), then variable suffix.
        var stable = """
            You are composing one section of a four-section private reading for
            someone in the ShantiSangha app. They are reading another person —
            a friend who shared their birth chart with them.

            ## Composition rules

            POV: second-person to the viewer ("your Moon"), third-person about
            the subject ("their Saturn", referenced by NAME below). The
            viewer is the one reading; the subject is who is being read.

            Length: around 150–200 words, two or three short paragraphs.

            Specificity: name the placements you're reading — the sign, the
            house in the relevant chart, the nakshatra, the dignity. When you
            describe how their planet lands in your house, name the house
            number (e.g. "their Saturn falls in your 7th house"). Texture
            beats label.

            Asymmetry: this is the viewer's reading of the subject. The
            subject is not seeing this. Speak honestly to the viewer about
            what they're meeting in this person, including the friction.

            Pattern, not fate: "tends to", "often", "the chart inclines you
            toward". No fixed predictions. No claims about marriage,
            longevity, illness, or specific events.

            Format: plain prose only. No headings, no bullets, no markdown,
            no quotations, no source citations.
            """;

        var focusText = section switch
        {
            PairReadingSection.WhatTheyBring =>
                "What this person brings into your life from the chart they were born with — the texture of their inner weather, the weight of their key placements, what their lagna and their strongest planets quietly transmit to the people around them. Read what their chart IS first, before any cross-chart talk.",
            PairReadingSection.WhereItEases =>
                "Where the two charts ease each other. Look for: their planets falling in your supportive houses (especially benefics in your kendras and trikonas), nakshatra friendship (same gana, friendly tara, complementary deities), Moon-sign element compatibility, dispositor friendships, dasha lords that play well together. Name the specific placements that flow.",
            PairReadingSection.WhereItAsksWork =>
                "Where the chart pair asks effort. Look for: their malefics (Saturn, Mars, Rahu, Ketu) on your sensitive houses (1, 4, 7, 10, 8, 12), bhakoot mismatch (their Moon-sign relative to yours in 6/8 or 2/12), nadi clash (same nadi), conflicting drives, dignity contrasts. Name what specifically is asking work and what work it's asking — patience, communication, holding space.",
            PairReadingSection.TheShape =>
                "The natural shape of this relationship from the chart-pair's pattern. What kind of bond does this combination support most easily — a teaching one, a peer one, a steadying one, a stretching one, a deeply committed one, a brief but vivid one? Read the dasha overlap if it informs the season.",
            _ => "Read what the chart pair shows."
        };

        var sb = new StringBuilder();
        sb.AppendLine();
        sb.AppendLine("## Section focus");
        sb.AppendLine(focusText);

        sb.AppendLine();
        sb.AppendLine("## Your chart (viewer)");
        sb.AppendLine(FormatChartFacts(viewer));

        sb.AppendLine();
        sb.AppendLine("## Their chart (subject)");
        sb.AppendLine(FormatChartFacts(subject));

        sb.AppendLine();
        sb.AppendLine("## Cross-chart facts");
        sb.AppendLine(crossFacts.PromptText);

        sb.AppendLine();
        sb.AppendLine("## Classical passages for the placements above");
        sb.AppendLine("These are the tradition's readings of placements appearing in either chart. Use them as substrate — interpret, don't quote.");
        sb.AppendLine();
        if (passages.Count == 0)
        {
            sb.AppendLine("(No passages matched.)");
        }
        else
        {
            foreach (var p in passages)
            {
                var header = string.IsNullOrWhiteSpace(p.Title) ? p.Source : p.Title;
                sb.AppendLine($"— {header}");
                sb.AppendLine(p.Content.Trim());
                sb.AppendLine();
            }
        }

        return stable + "\n" + sb.ToString();
    }

    private static string FormatChartFacts(JyotishContext ctx)
    {
        var chart = ctx.Chart!;
        var sb = new StringBuilder();
        var birthLine = $"Born {chart.BirthDate} at {chart.BirthTime}";
        if (!string.IsNullOrWhiteSpace(chart.BirthPlace)) birthLine += $" ({chart.BirthPlace})";
        sb.AppendLine(birthLine + ".");
        if (chart.Lagna is not null)
            sb.AppendLine($"Lagna: {chart.Lagna.Rashi}, {chart.Lagna.Degree:F2}°, in {chart.Lagna.Nakshatra} nakshatra (pada {chart.Lagna.Pada}).");
        foreach (var p in chart.Planets)
        {
            var house = p.House.HasValue ? $", house {p.House.Value}" : "";
            var flags = new List<string>();
            if (!string.IsNullOrWhiteSpace(p.Dignity) && p.Dignity != "Neutral") flags.Add(p.Dignity.ToLowerInvariant());
            if (p.Retrograde) flags.Add("retrograde");
            if (p.Combust) flags.Add("combust");
            var flagText = flags.Count > 0 ? $" [{string.Join(", ", flags)}]" : "";
            sb.AppendLine($"  {p.Name}: {p.Rashi}, {p.Degree:F2}°, in {p.Nakshatra} nakshatra (pada {p.Pada}){house}{flagText}");
        }
        if (!string.IsNullOrWhiteSpace(ctx.Mahadasha))
            sb.AppendLine($"Current Mahadasha: {ctx.Mahadasha}" +
                (string.IsNullOrWhiteSpace(ctx.Antardasha) ? "" : $" / Antardasha: {ctx.Antardasha}"));
        return sb.ToString();
    }

    // --- Cross-chart computation -----------------------------------------

    private record CrossChartFacts(
        IReadOnlyList<(string PlanetName, string Rashi, double Degree, int? HouseInViewerChart)> SubjectPlanetsInViewerHouses,
        IReadOnlyList<(string PlanetName, string Rashi, double Degree, int? HouseInSubjectChart)> ViewerPlanetsInSubjectHouses,
        string PromptText);

    private static CrossChartFacts ComputeCrossChartFacts(JyotishChartDetails viewer, JyotishChartDetails subject)
    {
        double? viewerLagna = SiderealOf(viewer.Lagna?.Rashi, viewer.Lagna?.Degree);
        double? subjectLagna = SiderealOf(subject.Lagna?.Rashi, subject.Lagna?.Degree);

        var subjectInViewer = subject.Planets.Select(p =>
        {
            int? house = null;
            var sidereal = SiderealOf(p.Rashi, p.Degree);
            if (viewerLagna.HasValue && sidereal.HasValue)
                house = HouseFrom(sidereal.Value, viewerLagna.Value);
            return (p.Name, p.Rashi, p.Degree, house);
        }).ToList();

        var viewerInSubject = viewer.Planets.Select(p =>
        {
            int? house = null;
            var sidereal = SiderealOf(p.Rashi, p.Degree);
            if (subjectLagna.HasValue && sidereal.HasValue)
                house = HouseFrom(sidereal.Value, subjectLagna.Value);
            return (p.Name, p.Rashi, p.Degree, house);
        }).ToList();

        var sb = new StringBuilder();
        sb.AppendLine("Their planets placed in YOUR house system:");
        foreach (var (name, rashi, deg, house) in subjectInViewer)
        {
            var label = house.HasValue ? $"your house {house.Value}" : "(no house)";
            sb.AppendLine($"  Their {name}: {rashi} {deg:F2}° → {label}");
        }
        sb.AppendLine();
        sb.AppendLine("Your planets placed in THEIR house system (for symmetry / dasha context):");
        foreach (var (name, rashi, deg, house) in viewerInSubject)
        {
            var label = house.HasValue ? $"their house {house.Value}" : "(no house)";
            sb.AppendLine($"  Your {name}: {rashi} {deg:F2}° → {label}");
        }

        return new CrossChartFacts(subjectInViewer, viewerInSubject, sb.ToString());
    }

    /// <summary>Sidereal longitude in [0, 360) from a rashi label and degree-in-rashi.</summary>
    private static double? SiderealOf(string? rashiLabel, double? degInRashi)
    {
        if (string.IsNullOrWhiteSpace(rashiLabel) || !degInRashi.HasValue) return null;
        var sanskrit = rashiLabel.Split(' ')[0].Trim().ToLowerInvariant();
        var idx = sanskrit switch
        {
            "mesha" => 0, "vrishabha" => 1, "mithuna" => 2, "karka" or "kataka" => 3,
            "simha" => 4, "kanya" => 5, "tula" or "thula" => 6, "vrischika" or "vrishchika" => 7,
            "dhanu" or "dhanus" => 8, "makara" => 9, "kumbha" => 10, "meena" => 11,
            _ => -1
        };
        if (idx < 0) return null;
        return idx * 30.0 + degInRashi.Value;
    }

    /// <summary>House (1-12) of a planet relative to a given lagna.</summary>
    private static int HouseFrom(double planetSidereal, double lagnaSidereal)
    {
        var diff = planetSidereal - lagnaSidereal;
        diff = ((diff % 360) + 360) % 360;  // normalize to [0, 360)
        return (int)(diff / 30) + 1;
    }

    // --- Persistence -----------------------------------------------------

    private async Task<PairReadingEntity> UpsertAsync(
        Guid viewerUserId,
        Guid subjectUserId,
        string chartHashPair,
        IReadOnlyDictionary<string, string> sections,
        IReadOnlyDictionary<string, string[]> usage,
        CancellationToken ct)
    {
        var sectionsJson = JsonSerializer.Serialize(sections);
        var usageJson = JsonSerializer.Serialize(usage);
        var now = DateTime.UtcNow;

        var existing = await db.PairReadings.FirstOrDefaultAsync(
            r => r.ViewerUserId == viewerUserId && r.SubjectUserId == subjectUserId, ct);
        if (existing is null)
        {
            existing = new PairReadingEntity
            {
                Id = Guid.NewGuid(),
                ViewerUserId = viewerUserId,
                SubjectUserId = subjectUserId,
                ChartHashPair = chartHashPair,
                SectionsJson = sectionsJson,
                PassageUsageJson = usageJson,
                GeneratedAt = now,
                UpdatedAt = now,
            };
            db.PairReadings.Add(existing);
        }
        else
        {
            existing.ChartHashPair = chartHashPair;
            existing.SectionsJson = sectionsJson;
            existing.PassageUsageJson = usageJson;
            existing.GeneratedAt = now;
            existing.UpdatedAt = now;
        }
        await db.SaveChangesAsync(ct);
        return existing;
    }

    private static string ComputeHash(JyotishContext? viewer, JyotishContext? subject)
    {
        var v = viewer?.Chart;
        var s = subject?.Chart;
        var parts = new[]
        {
            v?.BirthDate ?? "", v?.BirthTime ?? "", v?.BirthPlace ?? "",
            s?.BirthDate ?? "", s?.BirthTime ?? "", s?.BirthPlace ?? "",
            PairReadingVersion,
        };
        var bytes = Encoding.UTF8.GetBytes(string.Join("|", parts));
        return Convert.ToHexString(SHA256.HashData(bytes));
    }

    private static IReadOnlyDictionary<string, string> Deserialize(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new();
        }
        catch
        {
            return new Dictionary<string, string>();
        }
    }
}
