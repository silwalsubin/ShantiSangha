# 09 — Monthly Reflection

## Priority: Lower
## Phase: 3 — The Companion Grows
## Tab: Journey

## The Problem

The Journey tab shows streaks and stats, but there's no narrative. Numbers tell you what happened; a reflection tells you what it means. The user has no moment where the app says: "Here's who you were this month."

## What to Build

Once a month, generate and display a brief AI-written reflection on the user's month.

- Appears on the Journey tab at the start of each new month
- Not analytics. Not metrics. A letter:
  > "This month, you showed up for your practice 22 out of 30 days. You journaled about change, and your conversations kept returning to courage. You're growing."
- Draws from: check-in history, fulfilled commitments, daily reflections, goal progress
- One reflection per month. Cannot be regenerated or edited.
- Previous months' reflections are viewable in a simple list

## Why This Matters

This is the payoff for a month of practice. It's the app holding up a mirror and saying: "Look at who you've been becoming." It transforms scattered daily actions into a coherent narrative of growth.

## Scope

- Backend: scheduled job (Hangfire) that generates a monthly reflection using AI + user data
- Frontend: a card on Journey that shows the current/most recent monthly reflection
- A simple archive view for past months

## What This Replaces

Nothing. This adds a new rhythm to the app — daily check-ins and monthly reflection.

## Definition of Done

User opens Journey on the first week of the month and sees a warm, personal AI-generated reflection on their past month.
