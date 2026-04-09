# 10 — Grace Days for Streaks

## Priority: Lower
## Phase: 3 — The Companion Grows
## Tab: Home / Journey

## The Problem

Missing one day breaks a streak entirely. A user who meditated 29 out of 30 days sees their streak reset to 0. That's not discipline — that's punishment. It contradicts the app's principle of peace over pressure.

## What to Build

Allow 1 grace day per week for recurring goals — a missed day that doesn't break the streak.

- Grace days are automatic. The user doesn't need to "activate" them.
- Visual distinction: grace days show differently on the check-in calendar (e.g., a lighter shade vs full gold)
- Streak calculation: up to 1 unchecked day per 7-day window is tolerated
- The AI companion acknowledges grace days warmly: "Rest is part of the practice."

## Why This Matters

Real discipline includes rest. Spiritual traditions have sabbaths, fasting days, and retreat periods. A streak system that punishes any absence trains anxiety, not discipline. Grace days say: "You're human. One day off doesn't erase what you've built."

## Scope

- Backend: modify streak calculation logic to allow 1 gap per 7 days
- Frontend: visual distinction for grace days on the check-in calendar
- AI prompt: include grace day awareness in companion context

## What This Replaces

The current strict streak calculation where any missed day resets to 0.

## Definition of Done

User misses one day in a week and their streak continues. The calendar shows the missed day distinctly, and the experience feels compassionate, not lenient.
