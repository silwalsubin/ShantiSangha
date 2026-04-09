# 03 — Surface Journal Summaries

## Priority: High
## Phase: 1 — Make What Exists Feel Complete
## Tab: Reflect

## The Problem

Background jobs already extract AI summaries from journal entries, but the user never sees them. The work is done on the backend; it's just not displayed.

## What to Build

Show the AI-generated summary as a small card below each journal entry in the Reflect timeline and on the journal detail/edit view.

- One sentence summary: "You reflected on patience and the difficulty of slowing down."
- Subtle styling — this is a mirror, not a headline
- Only show if a summary exists (don't block on generation)

## Why This Matters

When the app summarizes what you wrote, it makes you feel heard. The user wrote something vulnerable, and the app understood it. This is a small UI change with outsized emotional impact.

It also validates that the insights pipeline is working and visible, which builds trust in the Journey tab's insights view.

## Scope

- Frontend only: display the existing `summary` field from journal API responses
- One component, used in the Reflect timeline and journal detail view
- No new API endpoints needed

## What This Replaces

Nothing. This surfaces data that already exists but is invisible.

## Definition of Done

User writes a journal entry, returns later, and sees a one-line AI summary beneath it.
