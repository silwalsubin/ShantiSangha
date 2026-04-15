# Home

## Purpose
The daily landing page. Sets the tone for the user's practice and surfaces the two things that matter today: the reflection and the practices.

## Value
- First thing users see — determines if they engage or leave
- The daily reflection gives them a reason to open the app (something they didn't ask for, written about them)
- Practice progress circles show at-a-glance whether today's discipline is done
- Quick check-in actions reduce friction

## How it works
- Time-aware greeting (morning/afternoon/evening)
- Daily reflection card below the greeting (see `docs/features/reflection.md`)
- Progress circles for recurring practices and one-time goals
- Check-in flow for each practice/goal
- FAB for adding a new task
- Evening nudge card appears after 6 PM if practices are still undone

## Key files
- iOS: `ios/ShantiSangha/Views/HomeView.swift`
- Frontend: `frontend/src/pages/app/home.vue`

## Data sources
- `/api/reflection/today?date=YYYY-MM-DD` — today's AI reflection
- `/api/goals/today?date=YYYY-MM-DD` — today's recurring practices
- `/api/goals?date=YYYY-MM-DD` — all goals (for milestone circle)
