# Journal

## Purpose
A private writing space for self-reflection. Users capture thoughts, process emotions, and build self-awareness through regular writing practice.

## Value
- Writing externalizes internal chaos — makes feelings tangible and manageable
- Creates a personal record of growth over time

## How it works
- User writes entries with optional title
- Entries are editable and deletable
- Paginated list view with content preview

## Key files
- Frontend: `frontend/src/pages/app/reflect/journal-new.vue`, `frontend/src/pages/app/reflect/journal-edit.vue`
- Backend controller: `backend/ShantiSangha.Journal/Controllers/JournalsController.cs`

## API endpoints
- `GET /api/journals` — list entries (paginated)
- `POST /api/journals` — create entry
- `GET /api/journals/{id}` — get single entry
- `PATCH /api/journals/{id}` — update entry
- `DELETE /api/journals/{id}` — delete entry

## Q2 improvements planned
- ~~Guided prompts~~ — done 2026-08: `GET /api/journal/prompt` serves a personalized opening question drawn from the user's memory (see memory.md)
- Emotion/theme tagging
