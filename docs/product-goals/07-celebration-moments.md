# 07 — Celebration Moments

## Priority: Medium
## Phase: 2 — Deepen the Daily Loop
## Tab: Home

## The Problem

Spiritual feedback messages already appear at streak milestones (day 1, 3, 7, 14, 21, 30), but they're inline text. Hitting 30 consecutive days of meditation should feel like a moment — not just another line of text in a list.

## What to Build

A brief, elevated visual moment when the user hits a meaningful streak milestone.

- Triggered at key thresholds: 7, 21, 30, 60, 90, 180, 365 days
- A simple overlay or expanded card with:
  - The streak number, large and prominent
  - A curated verse about perseverance or devotion
  - A warm message: "You've shown up for your practice every day for 30 days. That's not discipline — that's devotion to yourself."
- Dismisses with a single tap
- Not a badge, not a trophy, not gamification — a moment of recognition

## Why This Matters

Consistency is hard. When someone meditates for 30 straight days, the app should honor that. Not with points or badges, but with genuine acknowledgment. This is the app saying: "I see what you're doing. It matters."

## Scope

- Frontend: overlay component triggered by streak threshold
- Content: curated messages + verses for each milestone (small, finite set)
- Lightweight — no animations, no confetti, no sound effects

## What This Replaces

Enhances the existing spiritual feedback messages at milestones. The inline text remains for smaller streaks; the elevated moment is reserved for significant ones.

## Definition of Done

User hits a 7-day streak and sees a brief, warm, visually elevated acknowledgment of their consistency.
