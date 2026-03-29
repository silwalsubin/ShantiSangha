# Mood Check-ins

## Purpose
Simple daily emotional tracking that helps users notice patterns in how they feel over time. The foundation of self-awareness practice.

## Value
- Takes 10 seconds — low friction daily habit
- Trend visualization makes emotional patterns visible
- Data feeds into AI companion context (Q2) for personalized guidance
- Builds the daily return habit that keeps users engaged

## How it works
- User rates mood 1-10 with optional notes
- Scores stored with timestamp
- Trends endpoint calculates:
  - Overall average score
  - Direction (improving/stable/declining) by comparing first vs second half
  - Daily averages for bar chart visualization
- Dashboard shows quick check-in card and trend summary

## Key files
- Frontend: `frontend/src/pages/app/mood/index.vue`
- Dashboard check-in: `frontend/src/pages/app/dashboard.vue`
- Backend routes: `backend/ShantiSangha.Api/Routes/MoodRoutes.cs`

## API endpoints
- `POST /api/moods` — create check-in (score 1-10, optional notes)
- `GET /api/moods` — list check-ins (date filtering, pagination)
- `GET /api/moods/trends` — trend data (average, direction, daily chart)

## Q2 improvements planned
- Streak tracking for consecutive check-in days
- Weekly reflection summaries
- Emotional trend charts over weeks/months
- Feed mood data into AI companion system prompt
