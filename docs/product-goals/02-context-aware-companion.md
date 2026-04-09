# 02 — Context-Aware AI Companion

## Priority: Highest
## Phase: 1 — Make What Exists Feel Complete
## Tab: Reflect (Chat)
## Status: IMPLEMENTED

## The Problem

The AI chat works technically — streaming, history, clean UI — but it has no idea who it's talking to. It doesn't know the user's goals, streaks, journal entries, or deeper intentions. It's a generic chat interface, not a companion.

This is the biggest gap in the app. The AI companion is the feature that makes ShantiSangha more than a habit tracker. Without context, it's just another ChatGPT wrapper.

## What Was Built

The AI system prompt is now enriched with the user's full personal context on every message:

1. **Display name** — used naturally in conversation
2. **Active goals** with full context:
   - Title, type (recurring vs one-time)
   - Current streak + longest streak (recurring)
   - Whether they checked in today (recurring)
   - Days remaining + completion status (one-time)
   - The "Deeper Why" — their spiritual/emotional intention
3. **Recent mood summary** — last 7 days averaged, with trend direction
4. **Recent conversation summaries** — last 3, for continuity across sessions
5. **Recent journal summaries** — last 3 AI-generated summaries from journal entries
6. **Semantically relevant insights** — up to 5 insights matched against the current message using pgvector embeddings, with fallback to recency

## Key Files Changed

- `backend/ShantiSangha.Shared/Models/GoalSummaryDto.cs` — enriched with LongestStreak, CheckedInToday, DaysRemaining, IsCompleted
- `backend/ShantiSangha.Goals/Services/GoalQueryService.cs` — populates all new fields from check-in data
- `backend/ShantiSangha.Chat/AI/ChatService.cs` — maps real goal data + fetches journal summaries in parallel
- `backend/ShantiSangha.Chat/AI/SystemPrompt.cs` — new "What they have been writing about" section for journal summaries
- `backend/ShantiSangha.Shared/Interfaces/ISummaryQueryService.cs` — added GetRecentJournalSummariesAsync
- `backend/ShantiSangha.Insights/Services/SummaryQueryService.cs` — implemented journal summary query

## What This Replaced

Hardcoded default values (LongestStreak: 0, CheckedInToday: null, DaysRemaining: null, IsCompleted: false) in the GoalContext mapping, and the absence of journal summaries in the AI's awareness.

## Definition of Done

User opens a new conversation and the AI references their goals, streaks, journal reflections, or recent insights without being asked. ✅
