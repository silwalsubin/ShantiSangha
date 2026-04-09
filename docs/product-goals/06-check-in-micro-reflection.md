# 06 — Check-in Micro-Reflection

## Priority: Medium
## Phase: 2 — Deepen the Daily Loop
## Tab: Home

## The Problem

Check-ins are binary: Done or Skip. There's no space for the user to say *how* it went. A meditation session where you couldn't focus is very different from one where you found stillness — but both are just "Done."

## What to Build

An optional one-line note field that appears after tapping "Done" on a recurring goal check-in.

- Prompt: "How did it go?" or "One word for today's practice:"
- Completely optional — user can dismiss or ignore it
- The note is saved to the existing `GoalCheckIn.Note` field (already in the data model)
- Notes feed into the AI companion's context (ties into goal #02)

## Why This Matters

This turns a checkbox into a micro-reflection. Over time, these notes create a rich history of the user's practice that the AI can reference and the Journey tab can display. It also makes the user pause for one second after completing a practice — which deepens the ritual.

## Scope

- Frontend: expandable note field after check-in confirmation
- Backend: the `Note` field already exists on `GoalCheckIn` — just needs to be sent from the frontend
- No new endpoints needed

## What This Replaces

Nothing. Enhances the existing check-in flow without adding complexity (the note is optional).

## Definition of Done

User taps "Done" on a goal and optionally adds a one-line note about their practice.
