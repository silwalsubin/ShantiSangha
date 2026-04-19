# Jyotish Corpus — Status & What's Left

Snapshot of the pgvector-backed Jyotish passage corpus: what's ingested, what's deliberately skipped and why, and what would be needed to close remaining gaps.

## Current state (365 passages, all source-cited)

Every row carries `source_book`, `source_author`, `source_year`, `source_license`, `source_chapter`, and the `raw_source_excerpt` for audit. All 350 originally from pre-1929 public-domain sources; 15 passages newly added from Jataka Parijata 1932 (marked `acceptable_with_note` — see Sourcing policy below).

| Signature type | Count | Source | What it covers |
|---|---|---|---|
| `planet_in_house` | 84 | BJ Ch. XX (Chidambaram Aiyar 1905) | 7 classical planets × 12 houses (Sun, Moon, Mars, Mercury, Jupiter, Venus, Saturn) |
| `planet_in_house_with_ascendant` | 12 | BJ Ch. XX sub-variants | Dignity-aware compound signatures for 1st-house placements (e.g. `sun_in_h1__lagna_tula` = Sun debilitated) |
| `planet_in_sign` | 84 | BJ Chs. XVII–XVIII | 7 planets × 12 signs (every exaltation, debilitation, own sign, moolatrikona captured) |
| `planet_for_lagna` | 64 | Jataka Chandrika Stanzas 41–71 (Suryanarayana Row 1900) | Per-ascendant friend/foe classification: which planets are yogakarakas, benefics, or malefics for each of the 12 rising signs |
| `nakshatra` | 27 | BJ Ch. XVI | All 27 moon-in-nakshatra placements |
| `lagna` | 12 | BJ Ch. XVIII (Satyachariar section) | All 12 rising signs |
| `yoga` | 45 | BJ + **Jataka Parijata Adh. VII** | BJ: 39 (Raja Yoga, Akriti, Sankhya, Asraya, Dala, Chandra yogas, Ascetic Yoga). JP: 6 (5 Pancha Mahapurusha — Ruchaka/Bhadra/Hamsa/Malavya/Sasa — plus Neecha Bhanga Raja Yoga) |
| `conjunction` | 21 | BJ Ch. XIV | All two-planet conjunctions among the 7 classical planets |
| `avocation` | 7 | BJ Ch. X | Career indications by Navamsa lord of the 10th lord (one per planet) |
| `dasha` | **9** | **Jataka Parijata Adh. XVIII (Sastri 1932)** | All 9 mahadasha phalas (Sun, Moon, Mars, Mercury, Jupiter, Venus, Saturn, Rahu, Ketu) — unlocks the Mahadasha indicator in the chart UI |
| **Total** | **365** | | |

## Sourcing policy

Every passage is source-cited with `source_license` set to one of:
- `public_domain` — translator's work published pre-1929 (Chidambaram Aiyar, Suryanarayana Row, etc.)
- `acceptable_with_note` — post-1929 but author died > 60 years ago (Indian copyright expired), work openly republished on archive.org, no cleaner pre-1929 English equivalent exists. Currently: **Jataka Parijata tr. V. Subrahmanya Sastri 1932** (Sastri d. 1945 → PD in India since 2005). Closest clean alternative: Sanskrit Jataka Parijata (always PD but requires a translator).

Every chart element the app currently computes has a real classical passage attached — nakshatra, lagna, each planet row (with lagna-compound fallback, per-ascendant friend/foe fallback, and planet-in-sign fallback).

All 350 passages have been re-voiced to the **casual-astrologer register** — direct "you/your" address, contractions, short sentences, plain words. The interpretive core and source citations remain unchanged; only the register dropped. See `.claude/skills/jyotish-digest/SKILL.md` Rule 6 for the voice constraints that produce this tone.

## What's deliberately skipped

### Chapters not digested, with reasons

| Chapter | Topic | Why skipped |
|---|---|---|
| I–II | Zodiacal / Planetary definitions | Reference material, not interpretive passages |
| III | Animal and Vegetable Horoscopy | Not applicable to human natal charts |
| IV | Nishekakala (time of conception) | Conception timing, not natal interpretation |
| V | Birth-time matters | Calculation methodology, not interpretive |
| VI | Balarishta (Early death) | Anxiety-inducing event prediction; product-guardian rejects |
| VII | Ayurdaya (Lifespan determination) | Event prediction (death timing); against app mission |
| VIII | Dasa calculation | Describes how to compute dasa lengths, *not* per-planet dasa effects. BJ does not contain `jupiter_mahadasha`-style interpretations — those live in Phaladeepika / BPHS |
| IX | Ashtaka-Vargas | Numerical strength calculation, not interpretive |
| XIX | Planetary Aspects | 72 micro-passages (Moon-in-sign aspected by each planet), each source entry is 2–5 words. **Deferred** until chart engine wires aspect detection; wouldn't be retrievable until then |
| XXI | Planets in Several Vargas | Divisional chart calculation meta |
| XXII | Miscellaneous Yogas | Mostly technical (Karaka planet definitions, Sirodaya/Prishtodaya timing mechanics) — 1–2 digestible passages at best |
| XXIII | Malefic Yogas | Heavy event prediction: partner's mode of death, specific diseases, infertility. Violates skill rule 7 (no event prediction) and cuts against app mission |
| XXIV | Horoscopy of Women | Heavy patriarchal framing; needs substantial rewriting to produce neutral passages. Deferred rather than done poorly |
| XXV | Death | Event prediction; against app mission |
| XXVI | Lost Horoscopes | Technique for reconstructing unknown birth data, not natal interpretation |
| XXVII | Drekkanas | Iconographic mythic descriptions of 36 decan deities (e.g., "a man with a red cloth holding an axe"). Not psychological interpretation; doesn't fit app voice. Could be useful later if an imagery/symbol layer is built |
| XXVIII | Conclusion | Colophon |

## What's still a real gap

### 1. Dasha interpretations — ✅ RESOLVED

All 9 mahadasha phalas are now ingested (`dasha` signature type) from Jataka Parijata Adhyaya XVIII (V. Subrahmanya Sastri, 1932). Sourced under `acceptable_with_note` — see Sourcing Policy above. The Mahadasha indicator in the chart UI now retrieves a real passage.

### 2. Aspect-based retrieval

Ch. XIX aspects become useful once the chart engine computes aspect signatures. The backend can already determine which planet aspects which house (standard Jyotish aspect rules), but the current signature computation in `ChartSignatures.ComputeNatalSignatures` doesn't emit `moon_aspected_by_X` signatures.

**Next action:** extend `ChartSignatures.cs` to emit aspect signatures, then digest Ch. XIX (~72 passages). At that point, Moon-aspected-by-X becomes retrievable.

### 3. Nakshatra × Pada

Current nakshatra corpus (27 passages) is indexed by nakshatra only. Classical tradition (Brihat Parashara Nakshatra Chapter, or dedicated Nakshatra texts) provides pada-specific interpretations — 27 × 4 = 108 combinations. Not in BJ's chapter XVI at that granularity.

**Next action:** source a pada-level nakshatra text (possibly Nadi or classical texts with pada detail).

### 4. House-lord placement

Classical Jyotish leans heavily on "lord of Xth house placed in Yth house" — 12 × 12 = 144 meaningful combinations. **Not in BJ** (Varahamihira's focus is on planet placement, not lordship chain). Comes from BPHS and Phaladeepika.

**Next action:** BPHS (public-domain fragments) or Phaladeepika for lord-placement phalas.

### 5. Named yogas beyond BJ — ✅ PARTIAL

Pancha Mahapurusha (Ruchaka / Bhadra / Hamsa / Malavya / Sasa) and Neecha Bhanga Raja Yoga are now ingested from Jataka Parijata Adh. VII. Still open: **Gajakesari** (Moon–Jupiter kendra) and some Dhana Yogas — implied but not named. `conj_jupiter_moon` already covers the Gajakesari phenomenon in effect.

### 6. Rahu/Ketu per-house placements — STRUCTURAL GAP

Initially targeted for ingestion from Jataka Parijata, but on close inspection the classical Jyotish canon (BJ, JP, JC, Sarvartha Chintamani) does **not** provide systematic "Rahu in Nth house" or "Ketu in Nth house" individual phalas. Classical texts treat the nodes as modifiers in specific combinations (e.g. "Sun + Rahu in 4th", "Ketu + lord-of-6th"), not as primary agents in each bhava. The familiar per-house Rahu/Ketu tables are post-BPHS-Santhanam (1984) territory.

**Next action options:** (a) accept the canonical limitation and let the chart UI display Rahu/Ketu without a retrievable passage; (b) license a modern translation; (c) extract combination passages from JP Adh. XI–XV (Rahu + another planet in specific bhava) as compound signatures — technically faithful to the classical canon but requires chart-engine changes to emit the compound signatures.

## How to continue digestion

Use the `jyotish-digest` skill (`.claude/skills/jyotish-digest/SKILL.md`). It owns the full pipeline:

1. Source classical text → 2. Modernization → 3. JSON staging at `/tmp/jyotish_<topic>.json` → 4. DTO packaging via `jq` → 5. SSO-authenticated `curl` POST to `/api/jyotish/ingest/batch` → 6. Verification.

The skill also lists safe public-domain sources and refusal criteria (event-prediction content, copyrighted translations, caste/gendered framing).

## Verification

```bash
# Count by signature type
aws secretsmanager get-secret-value \
  --secret-id shantisangha/jyotish_admin_key \
  --profile AdministratorAccess-362249013106 \
  --query SecretString --output text | \
  xargs -I {} curl -sS -H "X-Admin-Key: {}" \
    https://shantisangha.com/api/jyotish/ingest/count
```

Expected output (as of last ingestion):
```json
{"total":365,"byType":[
  {"type":"avocation","count":7},
  {"type":"conjunction","count":21},
  {"type":"dasha","count":9},
  {"type":"lagna","count":12},
  {"type":"nakshatra","count":27},
  {"type":"planet_for_lagna","count":64},
  {"type":"planet_in_house","count":84},
  {"type":"planet_in_house_with_ascendant","count":12},
  {"type":"planet_in_sign","count":84},
  {"type":"yoga","count":45}
]}
```

## Priorities ranked by effort × value

1. **Chart-engine aspect detection + Ch. XIX digest** — adds aspect-aware interpretation to the chart page. Medium effort (chart engine change + 72 passages).
2. **House-lord placements** — 144 compound signatures for "lord of Xth in Yth." Classical Jyotish depth. JP Adh. XI–XV covers this; medium-high effort.
3. **Pada-level nakshatra source** — 81 new passages (27 extant × 3 additional padas each). Medium effort.
4. **Rahu/Ketu compound combinations** — JP Adh. XI–XV has "node + planet in specific bhava" passages. Requires chart-engine changes to emit compound signatures.
5. **Drekkana imagery layer** — iconographic descriptions, only useful if a symbol-rendering surface is built. Low priority.
