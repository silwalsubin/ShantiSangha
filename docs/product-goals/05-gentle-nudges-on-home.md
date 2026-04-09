# 05 — Gentle AI Nudges on Home

## Priority: Medium
## Phase: 2 — Deepen the Daily Loop
## Tab: Home

## The Problem

If the user opens the app in the evening and hasn't checked in, there's no acknowledgment of that. The app is silent. It doesn't encourage, and it doesn't guilt — but it also doesn't care. A companion should notice.

## What to Build

A warm, context-aware nudge that appears on the Home tab when goals haven't been checked in for the day.

- Appears only in the evening (after 6pm local time, or configurable)
- Tone: "Your meditation practice is waiting for you — no rush." Not: "You haven't checked in today!"
- Disappears once the user checks in or the day ends
- One nudge, not multiple. Don't nag.

## Why This Matters

This is the difference between a tool and a companion. The nudge says: "I notice you. I'm here. No pressure." It strengthens the daily return habit without creating anxiety.

## Scope

- Frontend: conditional rendering based on time + check-in status
- Content: a small set of rotating warm messages (5-10 variants)
- No push notifications. This only appears when the user is already in the app.

## What This Replaces

Nothing. This fills the gap between "all goals checked in" (green state) and "nothing done yet" (silent state).

## Definition of Done

User opens the app in the evening with unchecked goals and sees a gentle, warm message encouraging them — not guilting them.
