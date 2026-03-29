# Dashboard

## Purpose
The daily landing page. Sets the tone for the user's practice and provides quick access to everything that matters today.

## Value
- First thing users see — determines if they engage or leave
- Daily verse provides spiritual grounding and a reason to return
- Quick actions reduce friction to start any practice
- At-a-glance summaries show recent activity without navigating

## How it works
- Time-aware greeting (morning/afternoon/evening)
- Daily scripture verse (currently hardcoded, planned: rotating)
- Mood check-in card (disappears after today's check-in)
- Mood trend summary with bar chart
- Recent conversations list (last 3)
- Recent journal entries (last 2)
- Quick action buttons for new conversation and new journal

## Key files
- Frontend: `frontend/src/pages/app/dashboard.vue`
- Data comes from: `/api/moods/trends`, `/api/conversations?limit=3`, `/api/journals?limit=2`

## Q2 improvements planned
- "Today's practice" — personalized daily suggestion based on mood/history
- Practice streak counter
- Progress summary (meditation minutes, journal count, mood trend)
- Quick actions: "How am I feeling?", "Start a reflection", "Breathe"
- Rotating daily verses from Gita, Dhammapada, Upanishads
