# AI Spiritual Companion (Chat)

## Purpose
The core feature of ShantiSangha. A conversational AI that helps users process emotions, reflect on their inner state, and receive guidance grounded in spiritual wisdom.

## Value
- Provides a private, non-judgmental space to talk through feelings
- Available 24/7 — no appointment, no waiting
- Helps users who aren't ready for therapy but need more than journaling alone

## One mind, two doors (2026-08)
Both chat surfaces — the Reflect companion and the Home assistant — now run on ONE system prompt (`ShantiSangha.Shared/AI/UnifiedPrompt.cs`: companion warmth + the assistant's tool discipline) and ONE tool roster (`Kernel.CloneWithShantiSanghaTools` in ShantiSangha.Tools: reminders, circles, agent_feedback). The prompt takes a `PromptSurface` because the rooms render differently: the assistant surface shows tappable reminder cards and accepts photos; Reflect is prose-only, so the model enumerates reminders in prose there. Safety (crisis keywords + OpenAI moderation, `ISafetyService` in Shared, implemented in Chat) now runs on both surfaces' input AND output. The reminder-scoped "Plan with assistant" prompt stays separate (`AgentSystemPrompt.BuildForReminder`). Guards: `AiEval.Tests/Shared/UnifiedPromptTests.cs` (deterministic) + `UnifiedPromptLiveEvalTests.cs` (gated tone-bleed/tool-discipline evals).

## Unified conversation store
The Chat module's `Conversations`/`Messages` tables are the single store for every AI thread in the app, discriminated by `Conversations.Type`: `general` = the Reflect companion, `assistant` = the Home assistant. The Agent module persists its turns through `IConversationStore` (Shared interface, implemented here) — no cross-module reference. Assistant messages carry `Messages.MetadataJson` (reminder ids + photo S3 key). Store appends deliberately do NOT publish `MessagesSavedEvent` (no poetic titles or memory self-indexing for assistant turns; assistant threads are titled from their first message — and `ChatQueryService.GetAllUserMessageRefsAsync` filters to `general` threads so the memory backfill job honors the same rule). Chat has no EF migrations baseline, so store schema changes ship as idempotent startup SQL in Program.cs. The legacy flat `AgentMessages` table was migrated into one "Earlier conversations" assistant thread per user; a guarded one-off in Program.cs drops it now that the backfill has run.

## How it works
- User creates a conversation and sends messages
- Backend streams responses via Server-Sent Events (SSE) using GPT-4o
- Messages are stored as conversation history for the user
- The companion uses the user's display name + recent conversation history for context
- Each conversation belongs to one user, identified via JWT `sub` claim

## Key files
- Frontend: `frontend/src/pages/app/reflect/index.vue`, `frontend/src/pages/app/reflect/chat.vue`
- Backend controller: `backend/ShantiSangha.Chat/Controllers/ConversationsController.cs`
- AI service: `backend/ShantiSangha.Chat/AI/ChatService.cs`

## API endpoints
- `GET /api/conversations` — list conversations
- `POST /api/conversations` — create conversation
- `GET /api/conversations/{id}` — get conversation with messages
- `DELETE /api/conversations/{id}` — delete conversation (also purges memory chunks)
- `POST /api/conversations/{id}/messages` — send message (SSE streaming response)
- `POST /api/conversations/{id}/opener` — companion speaks first: streams a personalized greeting into an empty conversation (SSE), drawn from the user's recent memory

## Q2 improvements planned
- Spiritual grounding (system prompt with Gita, Buddhist teachings)
- Contextual responses ("I feel anxious" → breathing exercise + teaching)
- Suggested prompts based on mood/time/activity
- Auto-generated conversation titles
- Crisis detection with helpline resources
