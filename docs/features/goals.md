# Goals & Self-Discipline

## Purpose

Help users define what matters to them and build the daily discipline to pursue it. This is not a task manager or a habit tracker — it's a space for personal intentions backed by honest daily accountability.

## Why this matters

People don't lack goals. They lack consistency. The gap between "I want to get in shape" and actually doing it every day is where most people fail. ShantiSangha bridges that gap by making daily accountability feel like a spiritual practice, not a chore.

The mood tracker asked "how do you feel?" — nobody cares. Goals ask "who do you want to become?" — that's worth coming back for.

## Core Concepts

### Intentions (not tasks)

Users set **intentions** — things they want to become or achieve, in their own words:
- "I want to get in shape"
- "I want to build profit in stocks"
- "I want to read more books"
- "I want to be more present with my family"
- "I want to learn Spanish"
- "I want to meditate daily"

These are not SMART goals with deadlines. They are directions. The app doesn't judge whether the goal is specific enough — it respects the user's words.

### Daily discipline check-in

Each day, the user sees their active goals and answers one question per goal:

**"Did you work toward this today?"**

- Yes — streak continues, optional note about what you did
- Not today — streak resets (or pauses with grace days?), optional note about what got in the way

That's it. No percentages, no progress bars, no gamification overload. Just honest daily accountability.

### Streaks

The streak is the core motivator:
- Visual counter: "12 days" next to each goal
- Longest streak recorded
- The pain of breaking a streak is the motivation (loss aversion)

### Reflection integration

When a user checks in on goals, the data flows into the AI companion:
- "I see you've been consistent with fitness for 15 days. What's been helping?"
- "You mentioned stocks were frustrating yesterday. Want to talk through it?"
- Goal check-in notes become searchable in the Journey

## Open Questions

1. **Grace days?** Should users get 1 rest day per week without breaking the streak? Or is strictness the point?
2. **Goal limit?** Should we cap active goals at 3-5 to prevent overwhelm? Or let users decide?
3. **Categories?** Should goals have categories (health, finance, learning, relationships) or stay freeform?
4. **Archiving?** Can users archive/complete a goal? What does "done" look like for "I want to be healthier"?
5. **Privacy?** Goals are deeply personal — same privacy rules as journals. Never shared, never analyzed for business.
6. **Sacred Scrolls integration?** Should the daily goal check-in be a card in the scroll flow? Or its own space?
7. **Weekly reflection?** Should the app generate a weekly discipline summary? "You worked toward fitness 5/7 days this week."
8. **Accountability partner?** Future feature — could two people share accountability? Or does that violate the privacy principle?

## Data Model (Draft)

```
Goal
  - Id (Guid)
  - UserId (Guid)
  - Title (string) — "I want to get in shape"
  - CreatedAt (DateTime)
  - ArchivedAt (DateTime?) — null if active
  - CurrentStreak (int) — computed or cached
  - LongestStreak (int) — cached

GoalCheckIn
  - Id (Guid)
  - GoalId (Guid)
  - Date (DateOnly) — one check-in per goal per day
  - Completed (bool) — did you work toward this today?
  - Note (string?) — optional, what you did or what got in the way
  - CreatedAt (DateTime)
```

## API Endpoints (Draft)

```
POST   /api/goals              — create a new goal
GET    /api/goals              — list active goals with current streaks
PATCH  /api/goals/{id}         — update title or archive
DELETE /api/goals/{id}         — delete goal and all check-ins

POST   /api/goals/{id}/checkin — daily check-in (completed: true/false, note?)
GET    /api/goals/{id}/history — check-in history for a goal
GET    /api/goals/today        — today's check-in status for all active goals
```

## UI Placement

### Sacred Scrolls (Home)
One card in the daily flow:
- Shows active goals with today's status
- Tap Yes/No per goal
- See current streak update in real-time

### Journey
- Discipline section showing streaks, consistency percentages, longest streaks
- Calendar heatmap showing which days you checked in

### Reflect
- Goal notes feed into the unified timeline alongside conversations and journals

### AI Companion
- System prompt includes active goals and recent check-ins
- Can ask about goals naturally: "How's the reading going?"
- Can offer encouragement when streaks are long or compassion when they break

## What this replaces

- **Mood check-in** — removed entirely. The daily discipline check-in is the new daily ritual.
- **Mood trends** — replaced by discipline streaks and consistency tracking in Journey

## What this does NOT replace

- Chat, Journal, Voice — these remain as reflection tools
- Insights — these still get extracted from conversations and journals
- Coping exercises — these may be suggested by the AI when someone is struggling with discipline
