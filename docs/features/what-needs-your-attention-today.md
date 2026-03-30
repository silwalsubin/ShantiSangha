# What Needs Your Attention Today

## Purpose

The daily home screen. Shows everything the user should care about right now — recurring tasks to check in on, milestones approaching or overdue, and milestones in progress. One glance tells them where they stand today.

## What Shows Up

### Recurring Tasks

All active recurring tasks appear here every day. Each one can be:

- **Not checked in** — shows the task with Done / Not today buttons
- **Completed** — green check circle, title struck through, spiritual feedback message
- **Skipped** — empty circle with skip icon, title normal, spiritual feedback message

### Milestones

All active (not completed, not archived) one-time goals appear below the recurring tasks. They show:

- Title
- Days remaining until target date
- "Today" if the deadline is today
- "Overdue" if the deadline has passed

Milestones are tappable — they navigate to the goal detail page.

## Check-In Flow

### Completing a recurring task

1. User taps **Done**
2. Task transitions to completed state: green check circle, strikethrough title, green-tinted background
3. A spiritual feedback message appears below, contextual to the streak:
   - Day 1: "A single step. That is all it ever takes."
   - Day 3: "Three days. A pattern is forming. Stay with it."
   - Day 7: "One full week. Your discipline is becoming devotion."
   - Day 14, 21, 30: increasingly meaningful milestone messages
   - New personal record: "A new personal record. You have surpassed your past self."
   - Generic ongoing: "Another day honored. The practice deepens."

### Skipping a recurring task

1. User taps **Not today**
2. Task transitions to skipped state: empty circle with skip icon, neutral background
3. A gentle, non-shaming message appears:
   - "Rest is also practice. Tomorrow is a new beginning."
   - "The path does not disappear because you paused. It waits."
   - "Be gentle with yourself. Even the moon wanes before it grows full again."
   - If they had a long streak: "A pause is not a failure. Even the river rests in still pools before flowing on."

### Undoing a check-in

Not currently supported. If the user checks in by mistake, they would need to check in again tomorrow. This is intentional — the daily check-in is a commitment, not a toggle.

## Layout

```
YOUR DHARMA                          (label)
What needs your attention today?     (heading)

[ ] Meditate                    (recurring icon)
    [Done] [Not today]

[x] Exercise                    (recurring icon)
    "Another day honored..."

---

(target) Run a marathon            45d left
(target) Save $5000               Overdue

+ Add task
```

## Empty State

When the user has no tasks at all (no recurring, no milestones):

```
YOUR DHARMA
What needs your attention today?

You haven't set any tasks yet.

[Set your first task]
```

## Visual Design

- **Recurring task (pending):** Empty circle, dark title, Done/Not today buttons
- **Recurring task (done):** Green gradient circle with white check, green strikethrough title, green-tinted row
- **Recurring task (skipped):** Empty circle with skip icon, normal title, neutral row
- **Milestone:** Target icon, title, days remaining in saffron
- **Recurring icon:** Subtle cycle-arrows icon on the right of each recurring task row
- All items follow the sacred aesthetic — saffron/gold, parchment backgrounds, no cold colors

## API Endpoints Used

```
GET /api/goals/today    — recurring tasks with today's check-in status
GET /api/goals          — all goals (filtered client-side for active milestones)
POST /api/goals/{id}/checkin — check in a recurring task (completed: true/false)
```

## Key Files

- Frontend: `frontend/src/pages/app/home.vue`
- Backend: `backend/ShantiSangha.Api/Routes/GoalRoutes.cs` (GetToday, ListGoals, CheckIn)
- AI context: `backend/ShantiSangha.Infrastructure/AI/SystemPrompt.cs` (goals fed into chat)

## How It Connects to the AI

The AI companion receives all goal data in its system prompt — titles, streaks, check-in status, milestone deadlines, and the deeper why. When the user opens a chat, the AI already knows what they're working on today and can reference it naturally.

## Future Considerations

- Undo/edit check-in within a grace period (e.g. 5 minutes after checking in)
- Reordering tasks by priority or drag-and-drop
- Grouping milestones by urgency (overdue, this week, this month)
- AI-generated daily summary: "You have 3 practices today and a milestone due in 5 days"
- Notifications/reminders for milestones approaching deadline
