using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.SemanticKernel.ChatCompletion;
using ShantiSangha.Jyotish.Data;
using ShantiSangha.Jyotish.Models;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Jyotish.Services;

/// <summary>
/// Composes the pre-generated chart reading. Each section runs an
/// independent LLM call with a bounded prompt — chart facts for the
/// section + retrieved corpus passages + strict composition rules.
///
/// The reading is cached per user, keyed by a hash of birth details. When
/// birth details change, the old row's hash no longer matches the current
/// chart's hash, and the next GET regenerates.
/// </summary>
public class ChartReadingService(
    JyotishDbContext db,
    IJyotishContextService jyotishContext,
    IJyotishKnowledgeService knowledge,
    IChatCompletionService chat,
    ILogger<ChartReadingService> logger) : IChartReadingService
{
    public async Task<ChartReading?> GetAsync(Guid userId, CancellationToken ct = default)
    {
        var row = await db.Readings.AsNoTracking().FirstOrDefaultAsync(r => r.UserId == userId, ct);
        if (row is null) return null;

        // Stale-hash check — if the user's current chart hashes differently
        // than what was stored, we don't return the stale reading.
        var jyotish = await jyotishContext.GetContextAsync(userId, DateOnly.FromDateTime(DateTime.UtcNow), ct);
        var currentHash = ComputeChartHash(jyotish);
        if (currentHash != row.ChartHash) return null;

        var sections = Deserialize(row.SectionsJson);
        return new ChartReading(sections, row.GeneratedAt);
    }

    public async Task<ChartReading> GenerateAsync(Guid userId, CancellationToken ct = default)
    {
        var jyotish = await jyotishContext.GetContextAsync(userId, DateOnly.FromDateTime(DateTime.UtcNow), ct);
        var chartHash = ComputeChartHash(jyotish);

        if (jyotish?.Chart is null)
        {
            // No chart to read (birth details missing). Persist an empty
            // reading with the current hash so we don't retry endlessly.
            var emptyRow = await UpsertAsync(userId, chartHash,
                new Dictionary<string, string>(), new Dictionary<string, string[]>(), ct);
            return new ChartReading(new Dictionary<string, string>(), emptyRow.GeneratedAt);
        }

        var sections = new Dictionary<string, string>();
        var usage = new Dictionary<string, string[]>();

        foreach (var section in ChartReadingSection.All)
        {
            try
            {
                var (prose, passageIds) = await ComposeSectionAsync(section, jyotish, ct);
                sections[section] = prose;
                usage[section] = passageIds;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex,
                    "Chart reading section '{Section}' failed for user {UserId}; storing empty",
                    section, userId);
                sections[section] = string.Empty;
                usage[section] = Array.Empty<string>();
            }
        }

        var row = await UpsertAsync(userId, chartHash, sections, usage, ct);
        return new ChartReading(sections, row.GeneratedAt);
    }

    public async Task InvalidateAsync(Guid userId, CancellationToken ct = default)
    {
        var row = await db.Readings.FirstOrDefaultAsync(r => r.UserId == userId, ct);
        if (row is not null)
        {
            db.Readings.Remove(row);
            await db.SaveChangesAsync(ct);
        }
    }

    // --- Section composition ----------------------------------------------

    private async Task<(string Prose, string[] PassageIds)> ComposeSectionAsync(
        string section, JyotishContext jyotish, CancellationToken ct)
    {
        var chart = jyotish.Chart!;
        var planetsForSection = SelectPlanetsForSection(section, chart);

        // Derive signatures only for the planets this section focuses on.
        // This keeps the passage list tight and section-relevant rather than
        // dumping the whole chart's 20-40 passages into every section prompt.
        var signatures = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in planetsForSection)
        {
            var planetKey = p.Name.ToLowerInvariant();
            var rashiKey = ExtractSanskritRashi(p.Rashi).ToLowerInvariant();
            signatures.Add($"{planetKey}_in_{rashiKey}");
            if (p.House.HasValue) signatures.Add($"{planetKey}_in_h{p.House.Value}");
        }

        // Moon nakshatra applies to emotional_nature
        if (section == ChartReadingSection.EmotionalNature)
        {
            var moon = chart.Planets.FirstOrDefault(p => p.Name == "Moon");
            if (moon is not null)
                signatures.Add($"moon_in_{NormalizeNakshatra(moon.Nakshatra)}");
        }

        // Lagna applies to essence
        if (section == ChartReadingSection.Essence && chart.Lagna is not null)
        {
            var lagnaRashi = ExtractSanskritRashi(chart.Lagna.Rashi).ToLowerInvariant();
            signatures.Add($"lagna_in_{lagnaRashi}");
        }

        // Current mahadasha applies to season
        if (section == ChartReadingSection.Season && !string.IsNullOrWhiteSpace(jyotish.Mahadasha))
            signatures.Add($"{jyotish.Mahadasha!.ToLowerInvariant()}_mahadasha");

        var passages = await knowledge.GetPassagesAsync(signatures, ct);
        var passageIds = passages.Select(p => p.Id).ToArray();

        var prompt = BuildSectionPrompt(section, jyotish, planetsForSection, passages);

        var history = new ChatHistory();
        history.AddSystemMessage(prompt);
        history.AddUserMessage("Compose this section now, following the rules above.");

        var result = await chat.GetChatMessageContentAsync(history, cancellationToken: ct);
        var prose = (result.Content ?? string.Empty).Trim();

        return (prose, passageIds);
    }

    private static IReadOnlyList<ChartPlanet> SelectPlanetsForSection(string section, JyotishChartDetails chart)
    {
        // Which planets' data each section reads. Kept explicit so the
        // sections stay focused — no throwing everything at every section.
        var names = section switch
        {
            ChartReadingSection.Essence => new[] { "Sun" },
            ChartReadingSection.EmotionalNature => new[] { "Moon" },
            ChartReadingSection.MindAndVoice => new[] { "Mercury" },
            ChartReadingSection.DriveAndAction => new[] { "Mars", "Sun" },
            ChartReadingSection.PathOfGrowth => new[] { "Saturn", "Rahu", "Ketu" },
            ChartReadingSection.Season => Array.Empty<string>(),  // dasha-driven
            _ => Array.Empty<string>()
        };
        return chart.Planets.Where(p => names.Contains(p.Name)).ToList();
    }

    private static string BuildSectionPrompt(
        string section,
        JyotishContext jyotish,
        IReadOnlyList<ChartPlanet> planets,
        IReadOnlyList<JyotishPassage> passages)
    {
        var chart = jyotish.Chart!;

        var focusText = section switch
        {
            ChartReadingSection.Essence =>
                "Core identity — how this person shows up in the world. Read the ascendant (lagna) as the shape of the self, and the Sun as its animating fire. This is the opening of the reading — set the tone, not the full story.",
            ChartReadingSection.EmotionalNature =>
                "The emotional life. Read the Moon — its sign, nakshatra, house, and dignity — as the inner weather this person lives in. Include the nakshatra's quality. Note if the Moon is exalted, debilitated, in its own sign, or otherwise dignified.",
            ChartReadingSection.MindAndVoice =>
                "The thinking and speaking life. Read Mercury — its placement, dignity, and any conjunctions or closeness to the Sun (combust). Speech, analysis, learning, communication.",
            ChartReadingSection.DriveAndAction =>
                "Energy, initiative, and will. Read Mars (and the Sun's drive). Notice dignity, retrograde, house. How this person pushes into the world, fights for what matters, takes risk.",
            ChartReadingSection.PathOfGrowth =>
                "The long work of becoming. Read Saturn (discipline, structure, maturation) and the Rahu–Ketu axis (the karmic line of evolution). Where does this person meet resistance that eventually teaches them?",
            ChartReadingSection.Season =>
                $"The current chapter of life, shaped by the running Mahadasha and Antardasha ({jyotish.Mahadasha ?? "(unknown)"}/{jyotish.Antardasha ?? "(unknown)"}). What is this season asking of them?",
            _ => "Read what the chart shows."
        };

        var chartFacts = new StringBuilder();
        if (section == ChartReadingSection.Essence && chart.Lagna is not null)
        {
            chartFacts.AppendLine($"Lagna: {chart.Lagna.Rashi}, {chart.Lagna.Degree:F2}°, in {chart.Lagna.Nakshatra} nakshatra (pada {chart.Lagna.Pada}).");
        }
        foreach (var p in planets)
        {
            var house = p.House.HasValue ? $", house {p.House.Value}" : "";
            var flags = new List<string>();
            if (!string.IsNullOrWhiteSpace(p.Dignity) && p.Dignity != "Neutral") flags.Add(p.Dignity.ToLowerInvariant());
            if (p.Retrograde) flags.Add("retrograde");
            if (p.Combust) flags.Add("combust");
            var flagText = flags.Count > 0 ? $" [{string.Join(", ", flags)}]" : "";
            chartFacts.AppendLine($"{p.Name}: {p.Rashi}, {p.Degree:F2}°, in {p.Nakshatra} nakshatra (pada {p.Pada}){house}{flagText}");
        }
        if (section == ChartReadingSection.Season)
        {
            if (!string.IsNullOrWhiteSpace(jyotish.Mahadasha))
                chartFacts.AppendLine($"Mahadasha: {jyotish.Mahadasha}");
            if (!string.IsNullOrWhiteSpace(jyotish.Antardasha))
                chartFacts.AppendLine($"Antardasha: {jyotish.Antardasha}");
        }

        var passageText = passages.Count > 0
            ? string.Join("\n\n", passages.Select(p =>
            {
                var header = string.IsNullOrWhiteSpace(p.Title) ? p.Source : p.Title;
                return $"— {header}\n{p.Content.Trim()}";
            }))
            : "(No passages matched for this section.)";

        return $$"""
            You are composing one section of a classical Vedic birth-chart reading.

            ## Section focus
            {{focusText}}

            ## Chart facts for this section
            These are the actual placements from this person's chart. Speak from
            them directly. Never hedge with "if X is strong" — you can see whether
            it is, right here.

            {{chartFacts}}

            ## Classical passages for these placements
            These are the tradition's readings of these specific placements.
            Weave their interpretive core into your prose. Do not quote, cite,
            or name sources. Do not invoke astrological concepts the passages
            don't teach.

            {{passageText}}

            ## Composition rules
            - 80–120 words. One or two short paragraphs.
            - Second-person, contemplative voice. "Your Moon..." / "Your Saturn..."
            - Speak the specific placements — name the sign, nakshatra, house,
              dignity. The person wants to be seen in their actual chart.
            - Use tendency language ("tends to", "often", "inclines toward"),
              never absolute predictions.
            - If the chart facts + passages don't cover the section's focus
              well, produce a shorter, humbler section rather than speculating
              to fill space.
            - Output plain prose only. No headings, no bullets, no markdown.
            """;
    }

    // --- Persistence ------------------------------------------------------

    private async Task<ChartReadingEntity> UpsertAsync(
        Guid userId,
        string chartHash,
        IReadOnlyDictionary<string, string> sections,
        IReadOnlyDictionary<string, string[]> usage,
        CancellationToken ct)
    {
        var sectionsJson = JsonSerializer.Serialize(sections);
        var usageJson = JsonSerializer.Serialize(usage);
        var now = DateTime.UtcNow;

        var existing = await db.Readings.FirstOrDefaultAsync(r => r.UserId == userId, ct);
        if (existing is null)
        {
            existing = new ChartReadingEntity
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                ChartHash = chartHash,
                SectionsJson = sectionsJson,
                PassageUsageJson = usageJson,
                GeneratedAt = now,
                UpdatedAt = now,
            };
            db.Readings.Add(existing);
        }
        else
        {
            existing.ChartHash = chartHash;
            existing.SectionsJson = sectionsJson;
            existing.PassageUsageJson = usageJson;
            existing.GeneratedAt = now;
            existing.UpdatedAt = now;
        }

        await db.SaveChangesAsync(ct);
        return existing;
    }

    // --- Hashing / parsing -----------------------------------------------

    private static string ComputeChartHash(JyotishContext? jyotish)
    {
        var chart = jyotish?.Chart;
        var parts = new[]
        {
            chart?.BirthDate ?? string.Empty,
            chart?.BirthTime ?? string.Empty,
            chart?.BirthPlace ?? string.Empty,
        };
        var source = string.Join("|", parts);
        var bytes = Encoding.UTF8.GetBytes(source);
        var hash = SHA256.HashData(bytes);
        return Convert.ToHexString(hash);
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

    private static string ExtractSanskritRashi(string rashiLabel)
    {
        var paren = rashiLabel.IndexOf('(');
        return (paren > 0 ? rashiLabel[..paren] : rashiLabel).Trim();
    }

    private static string NormalizeNakshatra(string name)
        => name.Replace(" ", "").Replace(".", "").Replace("_", "").ToLowerInvariant();
}
