# Personal AI Assistant for Goals

## Purpose

A spiritually intelligent AI assistant that helps users define, pursue, and achieve their goals — not through productivity hacks, but through deep understanding of who they are and what they need to grow. The assistant manages goals on the user's behalf, checks in with genuine care, offers spiritual wisdom when they're stuck, and celebrates their progress as a companion on the path.

This is not a task manager. This is not a habit tracker with streaks. This is a personal guide that understands your goals, knows your patterns, and meets you where you are — spiritually, emotionally, and practically.

## Why this matters

People don't fail at goals because they lack tools. They fail because they lack understanding — of themselves, of what's blocking them, of why the goal matters in the first place. A to-do list can't ask "Why does this goal feel heavy today?" A habit tracker can't notice that you've been avoiding your creative goals since a difficult conversation last week.

ShantiSangha's AI assistant bridges the gap between intention and action by bringing spiritual intelligence to goal management:

- It understands the **deeper why** behind each goal — not just "exercise daily" but the desire for self-respect, energy, or healing
- It recognizes **emotional and spiritual patterns** — when resistance is fear, when procrastination is grief, when overwork is avoidance
- It offers **wisdom, not just reminders** — drawing from spiritual traditions to reframe struggle as growth
- It holds the user **accountable with compassion** — honest without being harsh, encouraging without being hollow

## How It Works

### The AI as Goal Manager

The assistant is not a passive tracker. It actively manages the user's goal journey:

1. **Goal Discovery** — When a user shares a goal, the AI explores it with them. "You want to meditate daily — what's drawing you to that? What would change in your life if you held this practice?" This conversation surfaces the deeper intention, which becomes the foundation for meaningful support.

2. **Intelligent Check-ins** — The AI doesn't just ask "Did you do it?" It reads the moment. If the user has been journaling about stress, it might say: "I noticed you've been carrying a lot this week. How did your meditation practice hold up — was it a refuge or did it feel like one more thing?" The check-in adapts to context.

3. **Spiritual Reframing** — When users struggle, the AI draws on spiritual wisdom to help them see their challenges differently. A broken streak isn't failure — it's information. A missed deadline isn't defeat — it's an invitation to examine what's truly important. The AI helps users find meaning in difficulty, not just push through it.

4. **Pattern Recognition** — Over time, the AI learns the user's rhythms. It notices that they tend to drop exercise goals when work gets intense, or that they make the most progress on creative goals after journaling. These patterns become the basis for personalized guidance.

5. **Proactive Support** — The AI doesn't wait for check-ins. It might surface a goal in conversation when the moment is right: "You mentioned wanting to read more — I noticed you haven't logged any reading this week. Is something getting in the way, or has the desire shifted?" It manages goals as a living, breathing practice, not a static list.

### Two Types of Goals

#### Recurring Goals (Daily Practice)

Things you commit to doing regularly — the disciplines that shape who you're becoming.

**Examples:**
- "Meditate every day"
- "Exercise 3 times a week"
- "Read for 30 minutes daily"
- "No social media before noon"
- "Practice gratitude daily"

**How they work:**
- User sets a title and frequency (daily, or X times per week)
- The AI manages daily check-ins conversationally — not as a checklist, but as a caring inquiry
- Consistency is tracked, but the AI frames it as a practice, not a performance metric
- When the user misses days, the AI explores what happened rather than shaming

#### One-Time Goals (Milestones)

Things you want to achieve — the meaningful destinations on your path.

**Examples:**
- "Run a marathon by October 2026"
- "Save $5000 by December"
- "Launch my side project by Q3"
- "Read 12 books this year"
- "Learn to cook 10 recipes"

**How they work:**
- User sets a title and a target date
- The AI tracks progress through conversations, journal entries, and explicit updates
- As deadlines approach, the AI brings natural awareness without creating anxiety
- The AI helps break large goals into natural next steps when the user feels overwhelmed

### The Spiritual Intelligence Layer

What makes this different from every other goal tool is the spiritual dimension:

- **Seeing the whole person** — Goals don't exist in isolation. The AI understands that a fitness goal connects to self-worth, a creative goal connects to purpose, a financial goal connects to security and freedom. It speaks to the whole person, not just the task.

- **Honoring resistance** — When a user avoids a goal, the AI doesn't push harder. It gets curious. Sometimes resistance is wisdom — the goal has changed, or the approach needs adjusting. The AI helps users distinguish between fear that should be faced and intuition that should be followed.

- **Finding meaning in struggle** — Spiritual traditions teach that difficulty is not the opposite of progress — it's often the substance of it. The AI helps users see their challenges through this lens, transforming frustration into growth.

- **Celebrating the journey** — Not just "Congrats, you hit your streak!" but "You've shown up for your practice every day this week, even on the hard days. That's not discipline — that's devotion to yourself."

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
  - DeeperWhy (string?) — the spiritual/emotional intention behind the goal, surfaced through AI conversation
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
- The AI assistant surfaces relevant goals naturally in the daily flow
- Recurring goals appear as caring check-ins, not checkboxes
- One-time goals surface when the AI senses it's the right moment

### Journey
- Recurring: consistency patterns, personal records, practice evolution
- One-time: progress toward milestones, timeline, recent reflections
- Both types show in the active goals section

### Reflect
- Goal progress notes feed into the unified timeline
- User can add a progress note from the Reflect hub

### AI Companion (Chat)
- The AI has full context of all goals, their deeper intentions, and check-in history
- It weaves goal awareness into natural conversation
- It proactively raises goals when context is right — not as reminders, but as genuine care

## What this replaces

- **Mood check-in** — removed entirely. Goal check-ins through AI conversation are the new daily ritual.
- **Mood trends** — replaced by goal progress and practice consistency in Journey

## Open Questions

1. **Grace days for recurring?** Allow 1 skip per week without breaking streak?
2. **Goal limit?** Cap at 5-7 active goals, or unlimited?
3. **Sub-goals/milestones?** Should one-time goals have sub-steps? (probably too complex for now)
4. **Proactive AI timing?** How aggressively should the AI raise goals in conversation? Should the user control this?
5. **Celebration rituals?** What happens when you complete a one-time goal or hit a meaningful streak? A special moment in Sacred Scrolls?
6. **DeeperWhy capture?** Should this happen during goal creation (structured) or emerge naturally through conversation over time?
