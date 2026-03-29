# Journal

## Purpose
A private writing space for self-reflection. Users capture thoughts, process emotions, and build self-awareness through regular writing practice.

## Value
- Writing externalizes internal chaos — makes feelings tangible and manageable
- AI-generated summaries and insights help users see patterns they'd miss
- Creates a personal record of growth over time

## How it works
- User writes entries with optional title
- On save, background jobs generate:
  - **Summary** — concise recap of the entry
  - **Embeddings** — vector representation for semantic search
  - **Insights** — AI-extracted meaningful takeaways
- Entries are editable and deletable
- Paginated list view with content preview

## Key files
- Frontend: `frontend/src/pages/app/journal/index.vue`, `new.vue`, `[id].vue`
- Backend routes: `backend/ShantiSangha.Api/Routes/JournalRoutes.cs`
- Background jobs: `GenerateSummaryJob`, `GenerateEmbeddingJob`, `ExtractInsightsJob`

## API endpoints
- `GET /api/journals` — list entries (paginated)
- `POST /api/journals` — create entry
- `GET /api/journals/{id}` — get single entry
- `PATCH /api/journals/{id}` — update entry
- `DELETE /api/journals/{id}` — delete entry

## Q2 improvements planned
- Guided prompts ("What am I grateful for today?")
- Emotion/theme tagging
- AI-tagged patterns across entries
