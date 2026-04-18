# Jyotish Corpus

This directory contains the Vedic astrology knowledge corpus used by
`JyotishKnowledgeService` as invisible context for AI-generated content
(daily readings, reflections, whispers, chat, portrait).

## ⚠️ Current state: PLACEHOLDER

**`JyotishCorpus.json` currently contains 130 AI-synthesized passages.**
Their `source` fields are marked `"placeholder — AI-synthesized, pending
replacement with source-verified content"`. These are **not** excerpts or
paraphrases from actual classical translations. They match the corpus
schema and voice so the rest of the system can be developed and tested,
but they should be replaced before users see this content at scale.

## Replacement path

Use the `jyotish-digest` Claude skill to digest real public-domain
classical translations (Brihat Parashara Hora Shastra, Phaladeepika,
Saravali, Brihat Jataka, etc.) into source-cited JSON passages. The
skill enforces:

- Citation to the exact source, chapter, verse, translator, year
- Preservation of the raw source excerpt for audit
- Modernization of archaic language (strip "will/shall" prediction forms)
- Removal of outdated cultural framing (caste, gender, fate-as-event)
- App voice (2-4 sentences, under 60 words, observational not predictive)

Source translations to use (all public domain, pre-1929):
- B. Suryanarain Rao (BPHS, Brihat Jataka, Saravali, Jataka Parijata,
  Sarvartha Chintamani)
- V. Subrahmanya Sastri (Brihat Jataka 1918, Phaladeepika 1917)
- N. Chidambaram Aiyar (portions)
- Ernest Wood
- Sanskrit originals (always public domain)

**Not** public domain (don't use):
- R. Santhanam's translations (1984, still copyrighted)
- Komilla Sutton, David Frawley, Sanjay Rath — all copyrighted modern works

## Schema

Each passage:

```json
{
  "id": "kebab_case_unique_id",
  "signature_type": "planet_in_house | planet_in_sign | nakshatra | dasha | dasha_pair | yoga | transit_aspect",
  "signatures": ["saturn_in_h7"],
  "title": "Human-readable label (internal)",
  "content": "Modernized interpretation, app voice, 50-60 words max",
  "themes": ["keywords", "for_semantic_retrieval"],
  "polarity": "nourishing | challenging_with_depth | mixed",
  "source": "Exact citation — text, chapter, verse, translator, year",
  "raw_source_excerpt": "Verbatim original passage, preserved for audit",
  "scope": "lifetime | period_specific | daily"
}
```

## Retrieval architecture

- Loaded at startup from embedded resource (see `JyotishKnowledgeService`)
- Indexed by signature for O(1) lookup
- `ChartSignatures` computes the set of signatures applicable to a user's
  chart; retrieval returns matching passages
- In `GenerateDailyReadingJob`, a deterministic rotation by (userId, date)
  picks 2 passages per day as invisible LLM context

## Future: DB migration

When the corpus matures, migrate from embedded JSON to a Postgres table
with vector embeddings for semantic retrieval. JSON file remains the
source-of-truth seed for the import. See planned `JyotishPassages` table.
