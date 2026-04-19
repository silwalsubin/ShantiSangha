---
name: jyotish-digest
description: "Digests passages from public domain Vedic astrology (Jyotish) classical texts and ingests them into the ShantiSangha pgvector corpus behind the admin-key-gated `/api/jyotish/ingest/batch` endpoint. Use this skill whenever the user pastes or points to text from classical Jyotish sources (Brihat Parashara Hora Shastra, Phaladeepika, Saravali, Brihat Jataka, Jataka Parijata, Sarvartha Chintamani, Hora Sara) or their public domain English translations (Suryanarain Rao, Subrahmanya Sastri, Chidambaram Aiyar, Ernest Wood), asks to digest, modernize, convert, ingest, or produce passages, or mentions adding to the Jyotish corpus. The skill owns the full pipeline: sourcing → modernization → JSON staging → DTO packaging → SSO-authenticated ingestion via AWS CLI + curl. Produces source-cited passages that keep the tradition's interpretive core while removing archaic language, prediction-as-fate, and outdated cultural assumptions."
---

# Jyotish Corpus Digest

This skill converts passages from public domain Jyotish classical texts into JSON passages for ShantiSangha's knowledge corpus. Each produced passage is a faithful modernization — same interpretive core, different language — with precise source citation and the original excerpt preserved for auditability.

The reason this exists: the app's daily reading, portrait, and chat features need access to real Vedic wisdom, not AI-invented content. Public domain translations (pre-1929) carry the actual tradition; they just need language modernization to match the app's quiet, observational voice and to strip prediction-as-fate framing.

## Hard Rules (non-negotiable)

### 1. Never invent interpretation not present in the source

The source passage is the ground truth. If a topic isn't covered in the provided text, do not generate a passage for it — refuse and say so. If the source is ambiguous, the modernization stays ambiguous; don't fill gaps with invented confidence.

### 2. Always cite precisely

Every output passage includes:
- `source`: exact citation (e.g., `"Brihat Parashara Hora Shastra Ch. 34, verses 40-42, tr. Suryanarain Rao 1905"`)
- `raw_source_excerpt`: the original text verbatim, preserved for audit

If the user provides only an excerpt without clear provenance, ask for the full citation before proceeding.

### 3. Strip prediction-as-fate language

Classical translations often use absolute futures ("will suffer," "shall endure losses," "the native will marry late"). Convert these to **tendency language**:
- `will` → `tends to` / `often` / `is inclined to`
- `shall` → `may` / `can`
- `suffers` → `encounters` / `meets with` / `is challenged by`
- `gains` → `tends toward`

**Exception:** factual astronomical statements ("is in the 7th house," "rules Taurus") stay as-is.

### 4. Remove outdated cultural framing

- **Gendered assumptions** (e.g., "a man with this placement will have a quarrelsome wife") → rephrase in person-neutral terms
- **Caste language** → remove; describe the quality, not the social position
- **Professional fate** (e.g., "will be a king" or "will be a servant") → translate into the underlying theme (authority, service, responsibility)
- **Superstitious delivery** (e.g., "evil eye," "black magic") → describe the observable pattern the text is pointing to

### 5. Preserve the interpretive core

Don't soften past the point of accuracy. If the source says Saturn in the 7th classically indicates late marriage or partnership difficulties, say that. The modernization is in **tone and framing**, not in interpretation. Keep the teaching; change the voice.

### 6. App voice constraints

Every generated passage must:
- Be 2-4 sentences, maximum 60 words in the `content` field
- Be in English plain enough that a non-Sanskritist reads it comfortably
- Never use Sanskrit terms in the `content` field without immediate English explanation
- Use **no exclamation marks, no peppy language, no poetic filler** ("weaving through," "quiet momentum," etc.)
- Frame observations as **something the person's practice can work with**, not something happening to them
- End with invitation toward practice when natural, but never force it

### 7. Refuse when appropriate

Refuse and tell the user when:
- Source provenance is unclear or unverifiable
- Source doesn't actually cover the requested signature
- Source text appears to be from a copyrighted (post-1929) translation without permission
- User asks for prediction of specific events (career, marriage date, health events)
- Source is too brief to support the ~50-word output

## Input Expectations

The user provides:
1. **Source text** — a passage from a public domain classical translation, pasted inline or as a file path
2. **Citation** — text name, chapter, verse/section, translator, year
3. **Target signature(s)** — what chart signatures this passage should be indexed under (e.g., `saturn_in_h7`, `moon_in_mrigashirsha`, `jupiter_mahadasha`)

If any of these are missing, ask for them before generating.

## Output Schema

Each produced passage matches this JSON structure:

```json
{
  "id": "kebab_case_unique_id",
  "signature_type": "planet_in_house | planet_in_sign | nakshatra | dasha | dasha_pair | yoga | transit_aspect",
  "signatures": ["saturn_in_h7"],
  "title": "Saturn in the 7th House",
  "content": "Modernized 2-4 sentence paraphrase, 50-60 words max, app voice, no prediction language, no Sanskrit terms without gloss, ends pointing toward practice where natural.",
  "themes": ["patience", "partnership", "commitment"],
  "polarity": "nourishing | challenging_with_depth | mixed",
  "source": "Brihat Parashara Hora Shastra Ch. 34, verses 40-42, tr. B. Suryanarain Rao (1905)",
  "raw_source_excerpt": "The verbatim original passage, preserved for audit. May contain archaic English.",
  "scope": "lifetime | period_specific | daily"
}
```

### Field guidelines

- **`id`**: kebab-case, unique across the corpus. Match signature for planet-in-house (`saturn_h7`) or nakshatra (`moon_in_mrigashirsha`).
- **`signatures`**: include Sanskrit and English aliases where applicable (`moon_in_vrishabha` AND `moon_in_taurus`).
- **`themes`**: 3-6 keyword tags for semantic retrieval. Nouns or noun phrases, lowercase with underscores (`emotional_depth`, `slow_bonds`, `late_marriage_theme`).
- **`polarity`**:
  - `nourishing` — generally supportive placements (Jupiter in 1, Moon exalted, etc.)
  - `challenging_with_depth` — classical "difficult" placements where the difficulty teaches something (Saturn in 7, Rahu in 1)
  - `mixed` — context-dependent outcomes (most placements default to this)

## Modernization Examples

### Example 1 — Saturn in the 7th House

**Source (Brihat Parashara Hora Shastra Ch. 34, tr. B. Suryanarain Rao, 1905):**

> "Should Saturn be posited in the 7th house, the native will be late in marriage and may have a wife of a somewhat quarrelsome temperament; through his own folly he shall at times be involved in losses and through his own doing shall know the company of servants and those of inferior station."

**Output:**

```json
{
  "id": "saturn_in_h7",
  "signature_type": "planet_in_house",
  "signatures": ["saturn_in_h7"],
  "title": "Saturn in the 7th House",
  "content": "Saturn's placement here tends to delay partnership or make it arrive with more weight than expected. Relationships are the primary classroom — commitment, patience, and the slow work of being truly present. The connections that last are built on structure rather than sparks.",
  "themes": ["patience", "partnership", "late_bonds", "commitment", "relationships_as_teacher"],
  "polarity": "challenging_with_depth",
  "source": "Brihat Parashara Hora Shastra Ch. 34, tr. B. Suryanarain Rao (1905)",
  "raw_source_excerpt": "Should Saturn be posited in the 7th house, the native will be late in marriage and may have a wife of a somewhat quarrelsome temperament; through his own folly he shall at times be involved in losses and through his own doing shall know the company of servants and those of inferior station.",
  "scope": "lifetime"
}
```

Note the transformations:
- "will be late in marriage" → "tends to delay partnership" (prediction → tendency)
- "a wife of quarrelsome temperament" → "partnership ... with more weight than expected" (gendered + judgmental → neutral)
- "through his own folly ... servants and those of inferior station" → removed (caste framing not preserved)
- **Core preserved**: late/heavy partnerships, structural commitment, slow bonds

### Example 2 — Moon in Mrigashirsha

**Source (Brihat Jataka Ch. 5, tr. V. Subrahmanya Sastri, 1918):**

> "He whose Moon is in Mrigashira nakshatra is ever searching, fond of reading and of wandering, of a somewhat fickle disposition though pleasing in speech, often separated from his native place and engaged in the service of kings."

**Output:**

```json
{
  "id": "moon_in_mrigashirsha",
  "signature_type": "nakshatra",
  "signatures": ["moon_in_mrigashirsha"],
  "title": "Moon in Mrigashirsha",
  "content": "A seeking nature — the restlessness others diagnose is this mind doing its work. Reading, traveling, and asking the next question are native rhythms. Separation from homeland, or an unsettled relationship with home, is a common thread. Speech tends to be pleasing even when the seeker is unsettled inside.",
  "themes": ["seeking", "restlessness", "travel", "wandering_mind", "pleasing_speech", "home_displacement"],
  "polarity": "mixed",
  "source": "Brihat Jataka Ch. 5, tr. V. Subrahmanya Sastri (1918)",
  "raw_source_excerpt": "He whose Moon is in Mrigashira nakshatra is ever searching, fond of reading and of wandering, of a somewhat fickle disposition though pleasing in speech, often separated from his native place and engaged in the service of kings.",
  "scope": "lifetime"
}
```

Transformations:
- "he whose Moon" → "a seeking nature" (gender-neutral reframe)
- "of fickle disposition" → "restlessness others diagnose" (judgmental → observational)
- "service of kings" → removed (caste/professional fate not preserved)
- **Core preserved**: seeking, reading, travel, displacement, pleasing speech

## Multi-source synthesis

If the user provides multiple translations of the same topic (e.g., BPHS + Phaladeepika + Saravali all on Saturn in 7th), produce ONE passage that synthesizes across sources. Cite all of them:

```json
"source": "Brihat Parashara Hora Shastra Ch. 34 + Phaladeepika Ch. 10 + Saravali Ch. 40, all tr. Suryanarain Rao unless noted"
```

The `raw_source_excerpt` includes all three original passages, separated by source.

## Workflow

When invoked:

1. **Verify inputs.** Check that source text, citation, and target signature are all provided. Ask for any missing pieces.

2. **Verify source is public domain.** Translators like Suryanarain Rao, Subrahmanya Sastri, Chidambaram Aiyar, Ernest Wood (all pre-1929) are safe. R. Santhanam's translations (1984) are NOT public domain. Komilla Sutton, David Frawley, Sanjay Rath — all modern and copyrighted. Refuse if unsure.

3. **Verify source actually covers the signature.** Read the provided text. If it doesn't discuss the requested placement/nakshatra/dasha, tell the user and refuse.

4. **Apply the modernization rules** (tone, language, prediction stripping, cultural neutralization).

5. **Produce the JSON.** Include all required fields. Preserve the raw excerpt.

6. **Stage the batch.** Write the digested passages to a staging file under `/tmp/jyotish_<chapter_or_topic>.json` (not to a repo path). Never overwrite previously staged files; each digest run lives in its own file.

7. **Present for review.** Surface a representative sample (2 nourishing, 2 challenging_with_depth, 2 sub-variants) in chat so the user can sanity-check tone. Report the full file path so they can read the rest on disk.

8. **Package for ingestion.** Once approved, transform the skill's output shape (snake_case, with `raw_source_excerpt`) into the ingestion endpoint's DTO shape using `jq`:

   ```bash
   jq -s '
     [.[][] |
       {
         id: .id,
         signatureType: .signature_type,
         signatures: .signatures,
         title: .title,
         content: .content,
         themes: .themes,
         polarity: .polarity,
         scope: .scope,
         sourceBook: "<full book name>",
         sourceAuthor: "<translator name>",
         sourceYear: <translation year>,
         sourceLicense: "public_domain",
         sourceChapter: (.source | sub("^<book prefix>"; "") | sub(", tr\\..*$"; "")),
         sourceVerse: null,
         rawSourceExcerpt: .raw_source_excerpt,
         source: .source
       }
     ]
   ' /tmp/jyotish_<file>.json > /tmp/jyotish_ingest_payload_<topic>.json
   ```

9. **Ingest to the live corpus.** The corpus lives in Postgres (pgvector) behind an admin-key-gated endpoint. The key is auto-generated in Terraform and stored in AWS Secrets Manager; retrieve via SSO-authenticated AWS CLI, then POST:

   ```bash
   PROFILE=AdministratorAccess-362249013106   # or user's equivalent SSO profile
   ADMIN_KEY=$(aws secretsmanager get-secret-value \
     --secret-id shantisangha/jyotish_admin_key \
     --profile $PROFILE \
     --query SecretString --output text)

   curl -sS -X POST https://shantisangha.com/api/jyotish/ingest/batch \
     -H "Content-Type: application/json" \
     -H "X-Admin-Key: $ADMIN_KEY" \
     -d @/tmp/jyotish_ingest_payload_<topic>.json \
     --max-time 180

   # Verify the count went up:
   curl -sS -H "X-Admin-Key: $ADMIN_KEY" \
     https://shantisangha.com/api/jyotish/ingest/count
   ```

   The endpoint is upsert-idempotent by `id`, so re-ingesting is safe. Each passage's embedding is generated server-side on insert.

10. **If the user hasn't configured SSO yet**, point them at:
    - AWS Console → IAM Identity Center dashboard for the AWS access portal URL
    - `aws configure sso` locally with the portal URL, region (`us-east-1`), and session name (`shantisangha`)
    - The profile name will be `AdministratorAccess-<account-id>` by default

    Do NOT ever fall back to writing the corpus into a local JSON file — the old `JyotishCorpus.json` is deleted and the DB is the only source of truth.

## Public Domain Sources (safe to use)

| Source | Translator | Year | Notes |
|--------|-----------|------|-------|
| Brihat Jataka (Varahamihira, 6th c.) | V. Subrahmanya Sastri | 1918 | Public domain. Archive.org. |
| Brihat Jataka | B. Suryanarain Rao | 1895 | Public domain. |
| Brihat Parashara Hora Shastra | B. Suryanarain Rao (various editions) | late 1800s–1917 | Public domain for editions pre-1929. |
| Phaladeepika | V. Subrahmanya Sastri | 1917 | Public domain. |
| Saravali | B. Suryanarain Rao | early 1900s | Public domain. |
| Jataka Parijata | B. Suryanarain Rao | early 1900s | Public domain. |
| Sarvartha Chintamani | B. Suryanarain Rao | early 1900s | Public domain. |
| Sanskrit originals (all) | — | — | Ancient, always public domain. |

## NOT public domain (refuse unless licensed)

- R. Santhanam (1984 BPHS translation) — copyrighted
- Komilla Sutton (The Nakshatras, etc.) — copyrighted
- David Frawley — copyrighted
- Sanjay Rath — copyrighted
- P.V.R. Narasimha Rao — free distribution but verify exact license terms
- Any 21st-century Jyotish interpretation

## Refusal template

If you must refuse, say clearly what's missing or blocked and suggest the fix. Example:

> "I can't produce a passage from this — the provided text is from R. Santhanam's 1984 translation, which is still under copyright. For the same interpretation from a public domain source, try V. Subrahmanya Sastri's 1917 Phaladeepika (Ch. 10) or B. Suryanarain Rao's BPHS editions. I can digest those."
