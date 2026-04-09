# 04 — Weekly Insight on Journey

## Priority: High
## Phase: 1 — Make What Exists Feel Complete
## Tab: Journey

## The Problem

The Journey tab shows streaks, milestones, practice stats, and a link to the insights page. But insights feel buried — you have to navigate to a separate page and scroll through a list. The most meaningful insight of the week should find the user, not the other way around.

## What to Build

A single prominent card on the Journey tab's main view showing the top insight from the past 7 days.

- "This week, your reflections centered on..." or the most resonant extracted insight
- One card. Not a carousel, not a list, not a dashboard widget.
- Links to the full insights page for those who want more

## Why This Matters

Insights are the payoff of reflection. The user journals, talks to the AI, records voice notes — and the Journey tab should reward that practice by showing them what emerged. One well-placed insight is more powerful than a searchable database.

## Scope

- Backend: endpoint or query to get the most recent/relevant insight from the past 7 days
- Frontend: one card component on the Journey main view, above or below the weekly check-in visualization

## What This Replaces

The current "Recent Insights" section that shows the last 3 insights as a simple list. This replaces it with a single, more prominent, curated insight.

## Definition of Done

User opens Journey tab and immediately sees a meaningful insight from their past week without navigating anywhere.
