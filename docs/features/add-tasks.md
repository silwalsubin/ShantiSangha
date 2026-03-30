# Add Tasks

## Purpose

Let users create the commitments that matter to them — recurring daily practices and one-time milestones with deadlines. This is the entry point for building their dharma. Simple, fast, no friction.

## Two Task Types

### Recurring (Daily Practice)

Things the user commits to doing regularly. These become the daily check-in items on the home screen.

**Examples:**
- Meditate every day
- Exercise 3 times a week
- Read for 30 minutes daily
- No social media before noon

**What the user provides:**
- Title (required) — in their own words
- That's it. Frequency defaults to daily.

### Milestone (One-Time)

Things the user wants to achieve by a specific date. These show on the home screen as reminders of what they're working toward.

**Examples:**
- Run a marathon by October 2026
- Save $5000 by December
- Launch my side project by Q3
- Read 12 books this year

**What the user provides:**
- Title (required)
- Target date (required)

## Where It Lives

The "Add task" flow lives on the **home page** (`/app/home`):

- When the user has no tasks, the home page shows "You haven't set any tasks yet" with a "Set your first task" button
- When tasks exist, a "+ Add task" link appears below the task list
- Both open the same inline form

## How It Works

1. User taps "Set your first task" or "+ Add task"
2. Form appears inline (no modal, no new page)
3. User picks type: **Daily practice** or **Reach a milestone**
4. User enters a title
5. If milestone: user picks a target date
6. User taps Save
7. Task appears immediately in the list

## UI Behavior

- The type selector uses two pill buttons: "Daily practice" (flame icon) and "Reach a milestone" (target icon)
- Daily practice is selected by default
- Title input placeholder changes by type: "I want to practice..." vs "I want to achieve..."
- Save button is disabled until title is filled (and date is set for milestones)
- Cancel closes the form and resets state
- After saving, the form closes and the task list reloads

## Validation

- Title is required and cannot be empty
- Title must be unique per user (backend enforces)
- Target date is required for milestones
- Maximum 10 active tasks per user

## API

```
POST /api/goals
Body: {
  title: string,
  type: "Recurring" | "OneTime",
  targetDate?: string (ISO date, only for OneTime)
}
Response: 201 Created with goal object
```

## Key Files

- Frontend form: `frontend/src/pages/app/home.vue` (inline form in template)
- Backend endpoint: `backend/ShantiSangha.Api/Routes/GoalRoutes.cs` (CreateGoal)
- Model: `backend/ShantiSangha.Core/Models/Goal.cs`

## Future Considerations

- Frequency selection for recurring tasks (e.g. "3 times per week" instead of daily)
- DeeperWhy prompt during creation — ask "Why does this matter to you?" as an optional step
- AI-assisted task creation through chat — "I want to start meditating" triggers a goal creation flow in conversation
- Sub-tasks for milestones (e.g. "Week 1: Run 5K, Week 4: Run 10K")
