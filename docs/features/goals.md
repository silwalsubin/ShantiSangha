# Goals & Self-Discipline

## Purpose

Help users define what matters to them — both the daily habits they want to build and the milestones they want to reach. This is not a task manager. It's a space for personal intentions backed by honest accountability.

## Why this matters

People don't lack goals. They lack consistency for recurring ones and follow-through for one-time ones. ShantiSangha bridges both gaps by making accountability feel like a spiritual practice, not a chore.

## Two Types of Goals

### 1. Recurring Goals (Discipline)

Things you commit to doing regularly to build who you want to become.

**Examples:**
- "Meditate every day"
- "Exercise 3 times a week"
- "Read for 30 minutes daily"
- "No social media before noon"
- "Practice gratitude daily"

**How they work:**
- User sets a title and frequency (daily, or X times per week)
- Daily check-in: "Did you do this today?" → Yes / Not today
- Tracked by **streaks** — consecutive days/weeks of discipline
- Longest streak is recorded as a personal record
- Missing a day resets the streak (this is the motivation)

**What makes it sticky:**
- The streak is the hook — you don't want to break a 15-day streak
- The AI companion can reference it: "You've been meditating for 3 weeks straight. How has that changed things?"

### 2. One-Time Goals (Milestones)

Things you want to achieve by a specific date.

**Examples:**
- "Run a marathon by October 2026"
- "Save $5000 by December"
- "Launch my side project by Q3"
- "Read 12 books this year"
- "Learn to cook 10 recipes"

**How they work:**
- User sets a title and a target date
- Progress is tracked through **notes/updates** — the user logs progress whenever they want
- No daily check-in pressure — just periodic reflection
- When the date arrives or the goal is achieved, the user marks it complete or extends it
- The Journey page shows time remaining and recent progress notes

**What makes it sticky:**
- Seeing the deadline approach creates natural urgency
- Progress notes become a journal of the journey toward the goal
- The AI companion can ask: "Your marathon is 4 months away. How's training going?"

## How They Differ

| Aspect | Recurring | One-Time |
|---|---|---|
| Frequency | Daily / X per week | No schedule |
| Tracking | Streaks + consistency | Progress notes + deadline |
| Check-in | Daily Yes/No | Whenever you make progress |
| Motivation | Don't break the streak | Deadline approaching |
| Completion | Never "done" — it's a practice | Done when achieved or deadline passes |
| Sacred Scrolls | Shows in daily flow | Shows only when user logs progress |

## Data Model

```
Goal
  - Id (Guid)
  - UserId (Guid)
  - Title (string) — user's own words
  - Type (enum: Recurring, OneTime)
  - Frequency (enum?: Daily, Weekly) — only for Recurring
  - FrequencyTarget (int?) — e.g. 3 for "3 times per week", null for daily
  - TargetDate (DateOnly?) — only for OneTime
  - CompletedAt (DateTime?) — when a OneTime goal is achieved
  - ArchivedAt (DateTime?) — null if active
  - CreatedAt (DateTime)

GoalCheckIn
  - Id (Guid)
  - GoalId (Guid)
  - Date (DateOnly) — one check-in per goal per day
  - Completed (bool) — did you work toward this today?
  - Note (string?) — what you did or what got in the way
  - CreatedAt (DateTime)
```

Streak calculation (Recurring): count consecutive check-in days backwards from today where Completed == true.

Progress tracking (OneTime): count of check-ins with notes, days remaining until TargetDate.

## API Endpoints

```
POST   /api/goals                — create goal (type, title, frequency?, targetDate?)
GET    /api/goals                — list active goals with streaks/progress
PATCH  /api/goals/{id}           — update title, frequency, targetDate, archive, or mark complete
DELETE /api/goals/{id}           — delete goal and all check-ins

POST   /api/goals/{id}/checkin   — daily check-in (completed, note?)
GET    /api/goals/{id}/history   — check-in history for a goal (paginated)
GET    /api/goals/today          — today's status for all active recurring goals
```

## UI Placement

### Sacred Scrolls (Home)
- **Recurring goals** appear in the daily flow — "Did you do this today?" per goal
- **One-time goals** do NOT appear in daily flow (no daily pressure). They appear only when the user adds a progress note from Reflect or Journey.

### Journey
- **Recurring:** streaks, weekly discipline dots, longest streaks
- **One-time:** list with progress bar (days elapsed / total), recent notes, days remaining
- Both types show in the active goals section

### Reflect
- Goal progress notes feed into the unified timeline
- User can add a progress note from the Reflect hub

### AI Companion
- System prompt includes both types of goals
- Recurring: "You've been exercising for 12 days straight"
- One-time: "Your marathon is 4 months away. How's training?"

## What this replaces

- **Mood check-in** — removed entirely. Recurring goal check-ins are the new daily ritual.
- **Mood trends** — replaced by discipline streaks and goal progress in Journey

## Open Questions

1. **Grace days for recurring?** Allow 1 skip per week without breaking streak?
2. **Goal limit?** Cap at 5-7 active goals, or unlimited?
3. **Sub-goals/milestones?** Should one-time goals have sub-steps? (e.g. "Week 1: Run 5K, Week 4: Run 10K") — probably too complex for now
4. **Reminders?** Should the app remind you about one-time goals as the deadline approaches?
5. **Celebration?** What happens when you complete a one-time goal? Special card in Sacred Scrolls?
