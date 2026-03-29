# Saved Insights

## Purpose
AI-extracted meaningful takeaways from conversations and journal entries. The app's memory of what mattered most in a user's reflections.

## Value
- Users don't have to re-read entire conversations or journals to find key moments
- Patterns emerge over time ("you keep mentioning work stress on Mondays")
- Searchable via semantic search — find insights by meaning, not just keywords
- Preserves progress and growth markers

## How it works
- Background job (`ExtractInsightsJob`) runs after conversations and journal saves
- AI reads the content and extracts 1-3 concise insights
- Insights are stored with source type (conversation/journal) and embedding vectors
- Semantic search uses pgvector to find insights by meaning
- Users can delete insights they don't want

## Key files
- Frontend: `frontend/src/pages/app/insights/index.vue`
- Backend routes: `backend/ShantiSangha.Api/Routes/InsightRoutes.cs`
- Search: `backend/ShantiSangha.Api/Routes/SearchRoutes.cs`
- Background job: `backend/ShantiSangha.Infrastructure/Jobs/ExtractInsightsJob.cs`
- Search service: `backend/ShantiSangha.Infrastructure/AI/SemanticSearchService.cs`

## API endpoints
- `GET /api/insights` — list insights (paginated)
- `DELETE /api/insights/{id}` — delete insight
- `GET /api/search?q=...` — semantic search across insights and journals

## Q2 improvements planned
- Emotion/theme tagging on insights
- Surface relevant insights on dashboard
- Weekly insight summary
- Monthly review ("Your month in reflection")
