# Coping Exercises

## Purpose
Guided grounding and breathing exercises for moments of emotional overwhelm. Immediate, practical tools that help users self-regulate.

## Value
- Provides in-the-moment relief during stress, anxiety, or emotional heaviness
- Timer tracks practice duration — makes the effort feel real
- Session logging builds a practice history
- Bridges the gap between "I feel bad" and "I don't know what to do"

## How it works
- Static catalog of 8 exercises (box breathing, grounding, body scan, etc.)
- User selects an exercise → modal opens with description and timer
- Timer counts up while user practices
- On completion, session is logged with duration
- Exercise catalog is hardcoded in the backend (not database-driven)

## Key files
- Frontend: `frontend/src/pages/app/coping/index.vue`
- Backend routes: `backend/ShantiSangha.Api/Routes/CopingRoutes.cs`

## API endpoints
- `GET /api/exercises` — get exercise catalog
- `POST /api/exercises/{slug}/sessions` — log completed session (duration)
- `GET /api/exercises/sessions` — list past sessions (paginated)

## Q2 improvements planned
- Practice timer for silent meditation (standalone, not tied to exercise)
- Guided audio meditations (5-10 tracks)
- Sacred chants with loop/timer
- Practice minutes tracking in dashboard
