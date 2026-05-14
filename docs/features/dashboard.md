# Home

## Purpose
The daily landing page. Sets the tone for the day and surfaces what's coming next from the user's reminder list.

## Value
- First thing users see — determines if they engage or leave
- A clean view of upcoming reminders (birthdays, bills, appointments, todos) so the user knows what their day and week hold
- Quick access to the AI assistant via the chat pill at the bottom

## How it works
- Time-aware greeting (morning/afternoon/evening) above the day's date stamp
- Upcoming reminders list — overdue, due today, and the next 7/30-day horizon
- Chat pill above the tab bar — tap to talk to the AI agent, press-and-hold the mic to dictate
- Profile avatar in the top-right opens the profile menu; carries a bindi dot when there are unread notifications

## Key files
- iOS: `ios/ShantiSangha/Views/HomeView.swift`
- Frontend: `frontend/src/pages/app/home.vue`

## Data sources
- `/api/reminders` — full reminder list (filtered client-side by horizon)
- `/api/notifications/unread-count` — drives the avatar bindi dot
