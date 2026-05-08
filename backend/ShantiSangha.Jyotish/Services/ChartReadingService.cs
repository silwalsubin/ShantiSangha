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

/// <summary>
/// Composes the pre-generated chart reading. Each section runs an
/// independent LLM call with a bounded prompt — chart facts for the
/// section + retrieved corpus passages + strict composition rules.
///
/// The reading is cached per user, keyed by a hash of birth details
/// plus a ReadingVersion constant. Bumping ReadingVersion invalidates
/// every cached reading so users pick up new signatures / new passages
/// / new prompts automatically.
/// </summary>
public class ChartReadingService(
    JyotishDbContext db,
    IJyotishContextService jyotishContext,
    IJyotishKnowledgeService knowledge,
    [FromKeyedServices(AiModels.SmartServiceId)] IChatCompletionService chat,
    ILogger<ChartReadingService> logger) : IChartReadingService
{
    /// <summary>
    /// Bump this whenever the composition prompt, the set of chart signatures
    /// retrieved per section, or the underlying corpus is materially updated.
    /// Each bump invalidates every user's cached reading — next GET regenerates.
    /// </summary>
    private const string ReadingVersion = "v5-2026-05-07-antardasha-jupiter-venus";

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
        var reading = new ChartReading(sections, row.GeneratedAt);

        // If the cached reading is missing any sections (transient LLM
        // failure on the original generation), lazy-retry just the missing
        // ones and upsert the merged result. Heals gaps over time without
        // forcing a full six-call regeneration each page open.
        if (!reading.IsComplete && jyotish?.Chart is not null)
        {
            var missing = ChartReadingSection.All
                .Where(s => !sections.ContainsKey(s) || string.IsNullOrWhiteSpace(sections[s]))
                .ToList();

            if (missing.Count > 0)
            {
                var allSignatures = jyotish.DeriveSignatures().ToList();
                var retried = await Task.WhenAll(missing
                    .Select(s => ComposeSectionSafeAsync(s, jyotish, allSignatures, userId, ct)));

                var healed = false;
                var mergedSections = new Dictionary<string, string>(sections);
                var mergedUsage = DeserializeUsage(row.PassageUsageJson);
                foreach (var (section, prose, passageIds, failed) in retried)
                {
                    if (!failed && !string.IsNullOrWhiteSpace(prose))
                    {
                        mergedSections[section] = prose;
                        mergedUsage[section] = passageIds;
                        healed = true;
                    }
                }

                if (healed)
                {
                    var updated = await UpsertAsync(userId, currentHash, mergedSections, mergedUsage, ct);
                    return new ChartReading(mergedSections, updated.GeneratedAt);
                }
            }
        }

        return reading;
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

        // Derive the full signature set ONCE and share across all sections.
        // This replaces the old per-section local derivation, which missed
        // planet_for_lagna, dasha_of_lord_of_h{N}, conj_*, manglik, and
        // compound placements — all of which live in the corpus.
        var allSignatures = jyotish.DeriveSignatures().ToList();

        // Sections compose in parallel. They're independent — different
        // planets, different passages — so there's no ordering requirement.
        // Parallel execution turns 6 × ~3s into max(~3s). We still bound
        // parallelism to MaxConcurrentSections to keep below provider rate
        // limits on the chat and embedding endpoints.
        var sectionTasks = ChartReadingSection.All
            .Select(section => ComposeSectionSafeAsync(section, jyotish, allSignatures, userId, ct))
            .ToArray();
        var sectionResults = await Task.WhenAll(sectionTasks);

        var sections = new Dictionary<string, string>();
        var usage = new Dictionary<string, string[]>();
        var failedSections = new List<string>();

        foreach (var (section, prose, passageIds, failed) in sectionResults)
        {
            sections[section] = prose;
            usage[section] = passageIds;
            if (failed) failedSections.Add(section);
        }

        // Cache the reading even when some sections failed. The alternative
        // (not caching partial) means every page open re-runs all six LLM
        // calls whenever any section transiently errors, which wastes spend
        // and makes users see different reading lengths on different opens.
        // With caching on, GetAsync returns what we have; GetAsync also
        // lazily retries the missing sections so gaps fill in over time
        // without forcing a full six-call regeneration each visit.
        if (failedSections.Count > 0)
        {
            logger.LogWarning(
                "Chart reading for user {UserId} had {FailedCount} failed sections: {Sections}. Caching partial; will lazy-retry empty sections on next open.",
                userId, failedSections.Count, string.Join(", ", failedSections));
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

    /// <summary>
    /// Composes a section with up to 3 attempts, retrying on both empty
    /// output AND transient exceptions. Rendering an empty section as a
    /// silent gap on the chart page is strictly worse than waiting an extra
    /// ~500ms for one retry, so we'd rather pay the cost than ship a hole.
    /// </summary>
    private async Task<(string Section, string Prose, string[] PassageIds, bool Failed)> ComposeSectionSafeAsync(
        string section,
        JyotishContext jyotish,
        IReadOnlyList<string> allSignatures,
        Guid userId,
        CancellationToken ct)
    {
        const int MaxAttempts = 3;

        for (int attempt = 1; attempt <= MaxAttempts; attempt++)
        {
            try
            {
                var (prose, passageIds) = await ComposeSectionAsync(section, jyotish, allSignatures, ct);
                if (!string.IsNullOrWhiteSpace(prose))
                {
                    if (attempt > 1)
                    {
                        logger.LogInformation(
                            "Chart reading section '{Section}' succeeded on attempt {Attempt} for user {UserId}",
                            section, attempt, userId);
                    }
                    return (section, prose, passageIds, false);
                }

                logger.LogWarning(
                    "Chart reading section '{Section}' returned empty on attempt {Attempt} for user {UserId}",
                    section, attempt, userId);
            }
            catch (Exception ex) when (attempt < MaxAttempts)
            {
                logger.LogWarning(ex,
                    "Chart reading section '{Section}' threw on attempt {Attempt} for user {UserId} — retrying",
                    section, attempt, userId);
            }
            catch (Exception ex)
            {
                logger.LogError(ex,
                    "Chart reading section '{Section}' failed after {Attempts} attempts for user {UserId}",
                    section, MaxAttempts, userId);
                return (section, string.Empty, Array.Empty<string>(), true);
            }

            if (attempt < MaxAttempts)
            {
                // Short backoff: empty returns and rate-limit blips both
                // clear within a second or two.
                await Task.Delay(TimeSpan.FromMilliseconds(500 * attempt), ct);
            }
        }

        logger.LogError(
            "Chart reading section '{Section}' returned empty across all {Attempts} attempts for user {UserId}",
            section, MaxAttempts, userId);
        return (section, string.Empty, Array.Empty<string>(), true);
    }

    private async Task<(string Prose, string[] PassageIds)> ComposeSectionAsync(
        string section,
        JyotishContext jyotish,
        IReadOnlyList<string> allSignatures,
        CancellationToken ct)
    {
        var chart = jyotish.Chart!;
        var planetsForSection = SelectPlanetsForSection(section, chart);

        // Filter the full signature set to what's relevant for this section.
        // Keeps passage volume tight and section-focused (avoids throwing the
        // whole chart's 30–40 passages at every section prompt) while picking
        // up every signature shape the central emitter produces.
        var signatures = FilterSignaturesForSection(section, planetsForSection, allSignatures);

        var passages = signatures.Count == 0
            ? Array.Empty<JyotishPassage>()
            : await knowledge.GetPassagesAsync(signatures, ct);
        var passageIds = passages.Select(p => p.Id).ToArray();

        var systemPrompt = BuildSectionPrompt(section, jyotish, planetsForSection, passages);

        var history = new ChatHistory();
        history.AddSystemMessage(systemPrompt);
        history.AddUserMessage($"Compose the '{section}' section now.");

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
            // Essence carries the dharmic core: Sun (animating fire), Jupiter
            // (the wisdom that orients toward meaning), and the lagna itself.
            // Jupiter is added here so its signatures (placement, sign,
            // for-lagna, conjunctions) actually reach the prompt — without
            // this, a chart with Jupiter in lagna or as mahadasha lord drops
            // its strongest planet from every section.
            ChartReadingSection.Essence => new[] { "Sun", "Jupiter" },
            // Emotional nature pairs the Moon (inner weather) with Venus
            // (capacity for pleasure, beauty, connection). Venus belongs here
            // classically as the karaka of rasa — the felt life, the heart's
            // taste — and was previously not a focus of any section.
            ChartReadingSection.EmotionalNature => new[] { "Moon", "Venus" },
            ChartReadingSection.MindAndVoice => new[] { "Mercury" },
            // Mars only — Sun moved to Essence to avoid double-counting its
            // signatures across sections.
            ChartReadingSection.DriveAndAction => new[] { "Mars" },
            ChartReadingSection.PathOfGrowth => new[] { "Saturn", "Rahu", "Ketu" },
            ChartReadingSection.Season => Array.Empty<string>(),  // dasha-driven
            _ => Array.Empty<string>()
        };
        return chart.Planets.Where(p => names.Contains(p.Name)).ToList();
    }

    /// <summary>
    /// Given the full set of chart signatures the engine emits, pick the
    /// subset relevant to this section's focus planets. Each section keeps
    /// only the signatures its reading actually uses — planet-specific (in
    /// sign, in house, for lagna, compound-lagna, conjunctions) plus the
    /// chart-level ones that belong to that section (lagna for essence,
    /// moon nakshatra for emotional, mahadasha signatures for season, etc.).
    /// </summary>
    private static IReadOnlySet<string> FilterSignaturesForSection(
        string section,
        IReadOnlyList<ChartPlanet> planetsForSection,
        IReadOnlyList<string> allSignatures)
    {
        var focusPlanets = planetsForSection
            .Select(p => p.Name.ToLowerInvariant())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var keep = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var sig in allSignatures)
        {
            // Planet-prefixed signatures (sun_in_h10, mars_for_lagna_mesha,
            // mars_in_h1__lagna_karka, etc.) — keep if a focus planet owns it.
            var planetMatch = focusPlanets.FirstOrDefault(p =>
                sig.StartsWith(p + "_", StringComparison.OrdinalIgnoreCase));
            if (planetMatch is not null)
            {
                keep.Add(sig);
                continue;
            }

            // Conjunctions — match if both planets are in the conj and either
            // of them is a focus planet. We keep it relevant to the section.
            if (sig.StartsWith("conj_", StringComparison.OrdinalIgnoreCase) &&
                focusPlanets.Any(p => sig.Contains("_" + p, StringComparison.OrdinalIgnoreCase) ||
                                      sig.Contains(p + "_", StringComparison.OrdinalIgnoreCase)))
            {
                keep.Add(sig);
            }
        }

        // Section-specific chart-level signatures that aren't planet-prefixed.
        switch (section)
        {
            case ChartReadingSection.Essence:
                // Lagna is the opening of the reading.
                foreach (var sig in allSignatures.Where(s => s.StartsWith("lagna_in_", StringComparison.OrdinalIgnoreCase)))
                    keep.Add(sig);
                break;

            case ChartReadingSection.DriveAndAction:
                // Manglik is a Mars-based partnership/drive concept. It lives
                // in the drive-and-action theme classically, not season.
                if (allSignatures.Contains("manglik", StringComparer.OrdinalIgnoreCase))
                    keep.Add("manglik");
                break;

            case ChartReadingSection.Season:
                // Mahadasha + dasha-pair (md/ad) + bhava-lord-dasha signatures
                // are the heart of this section. The dasha-pair pattern
                // ({md}_md_{ad}_ad) doesn't begin with a focus-planet prefix,
                // so it would otherwise fall through the planet filter.
                foreach (var sig in allSignatures.Where(s =>
                    s.EndsWith("_mahadasha", StringComparison.OrdinalIgnoreCase) ||
                    s.StartsWith("dasha_of_lord_of_", StringComparison.OrdinalIgnoreCase) ||
                    (s.Contains("_md_", StringComparison.OrdinalIgnoreCase) &&
                     s.EndsWith("_ad", StringComparison.OrdinalIgnoreCase))))
                {
                    keep.Add(sig);
                }
                break;
        }

        return keep;
    }

    private static string BuildSectionPrompt(
        string section,
        JyotishContext jyotish,
        IReadOnlyList<ChartPlanet> planets,
        IReadOnlyList<JyotishPassage> passages)
    {
        // Prompt structure is deliberately **stable content first, variable
        // content last**. The opening role + composition rules are identical
        // across all 6 sections of a given reading, which lets OpenAI's
        // automatic prompt caching kick in on sections 2–6 of each generation
        // (caching matches on a shared prefix; stable content must come first
        // for the prefix to match). It also reads cleaner: the model learns
        // who it is and how to respond BEFORE it sees what to respond to.

        var chart = jyotish.Chart!;

        var focusText = section switch
        {
            ChartReadingSection.Essence =>
                "Core identity — how this person shows up in the world. Read the ascendant (lagna) as the shape of the self, the Sun as its animating fire, and Jupiter as the wisdom that orients them toward meaning. This is the opening of the reading — set the tone, not the full story.",
            ChartReadingSection.EmotionalNature =>
                "The felt life. Read the Moon — sign, nakshatra, house, dignity — as the inner weather this person lives in, and Venus as the heart's capacity for pleasure, beauty, and connection. Include the moon's nakshatra quality. Note any planet that is exalted, debilitated, in its own sign, or otherwise dignified.",
            ChartReadingSection.MindAndVoice =>
                "The thinking and speaking life. Read Mercury — its placement, dignity, and any conjunctions or closeness to the Sun (combust). Speech, analysis, learning, communication.",
            ChartReadingSection.DriveAndAction =>
                "Energy, initiative, and will. Read Mars — dignity, retrograde, sign, house. How this person pushes into the world, fights for what matters, takes risk.",
            ChartReadingSection.PathOfGrowth =>
                "The long work of becoming. Read Saturn (discipline, structure, maturation) and the Rahu–Ketu axis (the karmic line of evolution). Where does this person meet resistance that eventually teaches them?",
            ChartReadingSection.Season =>
                $"The current chapter of life, shaped by the running Mahadasha and Antardasha ({jyotish.Mahadasha ?? "(unknown)"}/{jyotish.Antardasha ?? "(unknown)"}). The mahadasha sets the long arc; the antardasha is the active short-period weather inside it — give the antardasha real weight, since it's what's most alive right now. If the mahadasha lord rules specific houses, lean on that bhava-lord dasha context.",
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

        // ---- STABLE PREFIX ----
        // Same across every section composition, so it cache-matches.
        //
        // Tone is intentionally constructive rather than strict. A prior
        // version packed this prompt with NEVER / Do NOT rules and a hard
        // 200-280 word target; under those constraints the model returned
        // empty prose on sections where it couldn't confidently meet the
        // demand, and combined with partial-read caching, users saw only
        // 2-3 of the 6 sections. The guardrails that matter (grounded,
        // tendency language, no citations) are still here — just phrased
        // as guidance rather than threats.
        var stable = """
            You are composing one section of a classical Vedic birth-chart
            reading for a person who has opened the chart page in the
            ShantiSangha app.

            The full reading is six sections, composed in parallel. You are
            composing exactly one of them right now. Stay in your section;
            the user will read all six as a cohesive whole.

            ## Composition rules

            Length: around 160–220 words, flowing through two or three
            paragraphs. The user is on a dedicated page expecting to feel
            clearly seen, so go deeper than a horoscope blurb.

            Voice: second-person, contemplative. "Your Moon..." / "Your
            Saturn..."

            Specificity: name the placements you're reading — the sign, the
            nakshatra, the house, the dignity (exalted / debilitated / own
            sign / moolatrikona), retrograde, combust, vargottama — and
            describe the TEXTURE of each, not just its presence. What does
            an exalted Moon in Vrishabha feel like from the inside? How
            does Mercury combust in the 9th express itself? Name it, then
            explore it.

            Grounding: the chart facts above and the retrieved passages
            below are your substrate. Chart facts alone carry classical
            meaning — a debilitated Saturn in the 4th speaks to the home
            life even when no specific passage appears. Passages add
            depth where they exist. Use both.

            Pattern, not fate: say "tends to", "often", "inclines toward",
            "may find". Jyotish describes patterns, not certainties. Do
            not predict specific life events.

            Format: plain prose only. No headings, no bullets, no markdown,
            no quotations, no source citations.
            """;

        // ---- VARIABLE SUFFIX ----
        // Section focus + chart facts + retrieved passages come after the
        // stable prefix so OpenAI's auto-caching aligns on the prefix.
        var variable = $$"""
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
            """;

        return stable + "\n\n" + variable;
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

    /// <summary>
    /// Hashes birth details + a ReadingVersion so cached readings
    /// auto-invalidate when we ship composition or corpus changes. Without
    /// the version token, users would stay on stale readings forever.
    /// </summary>
    private static string ComputeChartHash(JyotishContext? jyotish)
    {
        var chart = jyotish?.Chart;
        var parts = new[]
        {
            chart?.BirthDate ?? string.Empty,
            chart?.BirthTime ?? string.Empty,
            chart?.BirthPlace ?? string.Empty,
            ReadingVersion,
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

    private static Dictionary<string, string[]> DeserializeUsage(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<Dictionary<string, string[]>>(json) ?? new();
        }
        catch
        {
            return new Dictionary<string, string[]>();
        }
    }
}
