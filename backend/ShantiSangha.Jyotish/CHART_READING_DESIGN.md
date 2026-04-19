# Chart Reading Composition Layer — Design

> Status: **design, not implemented.** This doc captures the architecture agreed on so the build can pick up cleanly in a focused session.

## The problem this solves

Chat today is a per-turn operation:

1. User asks a question.
2. Backend pulls chart signatures → retrieves corpus passages → sends everything to the LLM.
3. LLM composes a response.

This means **every chart chat turn re-reads the chart from scratch.** The LLM has the raw chart + a pile of passages + the user's question, and has to select which placements matter, compose prose, and ground its claims in passages — all in one pass. Hedging (*"if Mercury is strong in your chart"*) creeps in because the LLM is doing too much at once under streaming pressure.

The cleaner design: **pre-compose a source-grounded reading of the whole chart once**, then chat questions ground in *that reading* plus the raw corpus. The LLM during chat becomes a reader of an already-composed reading, not the author of a new one each turn.

## What the reading is

A sectioned, classical, source-cited narrative of the full natal chart. Five to six sections, ~100 words each, ~500 words total. Every sentence traces back to a corpus passage or a raw chart fact.

Proposed sections (names are working labels, not user-facing copy):

| Key | Focus | Corpus signatures drawn from |
|---|---|---|
| `essence` | Core identity | `lagna_in_{rashi}`, Sun placements, key yogas the chart forms |
| `emotional_nature` | Moon life | `moon_in_{rashi}`, `moon_in_{nakshatra}`, moon dignity, moon yogas |
| `mind_and_voice` | Mercury life | `mercury_in_{rashi}`, `mercury_in_h{N}`, Mercury's dignity and conjunctions |
| `drive_and_action` | Mars + Sun | `mars_in_{rashi}`, `mars_in_h{N}`, Mars dignity, martial yogas |
| `path_of_growth` | Saturn + Rahu/Ketu | `saturn_in_{rashi}`, `saturn_in_h{N}`, Saturn dignity, ascetic/restraint yogas |
| `season` | Current life chapter | Current mahadasha/antardasha, transits that matter |

Each section is composed independently by the LLM in a bounded prompt that includes:

- The specific raw chart facts for that section (planet placements, dignity, flags)
- The retrieved corpus passages for those placements
- The section's framing instruction
- Strict no-speculation rules

## Where it lives

### Entity

```csharp
// backend/ShantiSangha.Jyotish/Models/ChartReadingEntity.cs
public class ChartReadingEntity
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }

    // The hash is computed from birth_date + birth_time + birth_place. Any
    // change invalidates the reading and triggers regeneration on next read.
    public string ChartHash { get; set; } = string.Empty;

    // JSON keyed by section name (see table above).
    // e.g. {"essence": "...", "emotional_nature": "...", ...}
    public string SectionsJson { get; set; } = "{}";

    // Provenance: which passage ids informed which section. Used for audit +
    // "show your work" features later.
    public string PassageUsageJson { get; set; } = "{}";

    public DateTime GeneratedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
```

### DbContext addition (Jyotish module already has `JyotishDbContext`)

Add `DbSet<ChartReadingEntity> Readings` plus an EF migration.

### Service

```csharp
// backend/ShantiSangha.Jyotish/Services/ChartReadingService.cs
public interface IChartReadingService
{
    Task<ChartReading?> GetAsync(Guid userId, CancellationToken ct = default);
    Task<ChartReading> GenerateAsync(Guid userId, CancellationToken ct = default);
}
```

`GenerateAsync` orchestrates:

1. Fetch the user's chart via `IJyotishContextService.GetContextAsync`.
2. Compute the `ChartHash` (date + time + place normalized).
3. For each section:
   - Gather the section-relevant chart facts.
   - Derive + retrieve corpus passages for those facts.
   - Compose prose via a bounded LLM call (Semantic Kernel + GPT-4o, same stack as daily reflection).
4. Persist to `ChartReadingEntity`, upsert by `(UserId, ChartHash)`.

Each section's LLM call is **~200 words of passages in, ~100 words of prose out**. No composition across sections — each is independent. Total: 6 small LLM calls per generation, budget maybe 10k–20k tokens.

### Endpoint

- `GET /api/jyotish/reading` — returns cached if chart-hash matches, otherwise triggers generation and returns result. Add a `?force=true` to bypass cache.
- `DELETE /api/jyotish/reading` — invalidate (for debug / re-roll).

### Background regeneration

When `/me` is PATCHed with new birth details, fire an event → Hangfire job → `ChartReadingService.GenerateAsync`. Pattern matches `GenerateDailyReadingJob` already in Wellness.

### Chat integration

Chart conversations (already routed via `ConversationType.Chart`) pull the pre-generated reading as primary context and use corpus passages as secondary grounding:

```csharp
if (isChart)
{
    var reading = await chartReadingService.GetAsync(userId, ct);  // cached or generated
    // Pass reading.Sections to SystemPrompt.ForChart alongside jyotish + passages
}
```

The chart prompt gets an additional block:

```
## This person's chart reading (composed in advance from the corpus)

### Essence
{essence_section_text}

### Emotional nature
{emotional_nature_section_text}
...
```

The chat LLM then reads from this narrative + the raw passages, rather than composing prose from scratch. Its job becomes: *"given the reading above and the question, surface the relevant section and deepen it with corpus passages."*

### iOS surface

On `VedicChartView`, insert a **Your Reading** card between the BIRTH card and the RASHI card. Shows the sections as expandable rows (tap title → reveal prose). Loading state: shimmer while generating on first open.

```
Your Reading
  Essence                         ▼
  Emotional Nature                ▼
  Mind and Voice                  ▼
  ...
```

## What this unlocks

1. **Chat grounded in a pre-composed, audited narrative** — LLM no longer composes from scratch per turn.
2. **Source citation feasible** — the `PassageUsageJson` maps each section back to specific corpus passages. Later, tapping a section can reveal which classical sources informed it.
3. **Independent regeneration** — rerun the reading with a better corpus (when Phaladeepika dasha phalas ingest, when aspect retrieval ships) without touching chat infra.
4. **Portrait + daily reflection reuse** — Wellness already generates `Portrait` (an identity-narrative blending chart + practice). The reading could feed into the portrait's chart half.

## Implementation order when we build this

1. Entity + migration (`ChartReadingEntity`, `jyotish_readings` table with `chart_hash` unique on user)
2. `ChartReadingService.GenerateAsync` — sections one at a time, starting with `emotional_nature` since that has the most corpus coverage today
3. `GET /api/jyotish/reading` endpoint
4. Hangfire job wired to birth-detail updates
5. iOS card on `VedicChartView`
6. Chat integration — inject reading into chart conversations

## Open questions

- **Stale reading policy.** Regenerate on birth-detail change (obvious). Regenerate on corpus expansion? Probably not automatically — too expensive. Maybe an admin "invalidate all readings" op that forces next-read regeneration.
- **Failure modes.** If a section's LLM call fails, do we persist partial? Retry? Current thinking: retry once per section, persist what succeeded, flag missing sections in the response so UI can show "still composing..."
- **Section weights.** Some charts have notable yogas (Gajakesari, etc.). Should a dedicated `notable_yogas` section exist when those are present, or fold them into `essence`? Design leans toward folding to keep section count stable.

## What this is NOT

- Not predictions. Not horoscopes. Not transit tracking. The reading is natal, lifetime-scope, based on the birth chart that doesn't change.
- Not user-editable. The reading is what the tradition sees; the user's voice comes through in chat and journal, not in the reading itself.
- Not replacing the chat surface. Chat stays. The reading grounds chat.
