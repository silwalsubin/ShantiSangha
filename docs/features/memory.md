# Memory

## Purpose
The connective tissue that makes the companion actually know the user. Everything the user writes — journal entries, voice-note transcripts (via their journal drafts), substantive chat messages — is embedded into pgvector and retrieved into the AI companion's context on every reply. The companion can recall "a few weeks ago you wrote about…" because it genuinely remembers.

## Value
- The app's soul principle ("the app knows you") implemented as infrastructure, not a feature screen
- Every future surface (proactive openers, Home continuity, insights) inherits it
- Creates the moat: the longer someone uses ShantiSangha, the better it knows them — no competitor starts with that context

## How it works
- **Ingest:** Journal, Chat, and Wellness publish events they already published (`JournalCreatedEvent`, `MessagesSavedEvent`, …). The Memory module subscribes, and thin handlers enqueue Hangfire jobs that pull content through the Shared query services (`IJournalQueryService`, `IChatQueryService`) — no cross-module table access.
- **Chunks:** one `MemoryChunk` row per source (journal entry or user chat message ≥ 40 chars), embedded with `text-embedding-3-small` (1536 dims), content-hashed so unchanged text is never re-embedded. Assistant replies are never indexed — memory is the user's life, not old bot output.
- **Retrieve:** `ChatService` embeds the incoming message, pulls top-5 nearest chunks (L2, loose distance cap, excluding the current conversation), and appends a "What you remember about this person" block to the system prompt — last, to preserve OpenAI prompt-cache prefix matching.
- **Forget:** deleting a journal or conversation publishes `JournalDeletedEvent` / `ConversationDeletedEvent`; Memory purges the chunks. Deleted words are forgotten everywhere.
- **Backfill:** `BackfillMemoryJob` runs on every boot (idempotent via content hashes) so pre-Memory history is indexed once.

## Key files
- Module: `backend/ShantiSangha.Memory/` (own `MemoryDbContext`, own migrations, references Shared only)
- Retrieval consumer: `backend/ShantiSangha.Chat/AI/ChatService.cs`, `SystemPrompt.cs`
- Contracts: `ShantiSangha.Shared/Interfaces/IMemoryQueryService.cs`, `Shared/Models/MemoryHit.cs`

## Surfaces powered by memory
- **Companion retrieval** — every chat reply is grounded in the user's own past words (invisible).
- **Companion speaks first** — `POST /api/conversations/{id}/opener` (SSE): a short personalized greeting streamed into a brand-new conversation, drawn from the most recent memories. iOS calls it from `ChatView` when an empty conversation opens; falls back to the static opening card on failure.
- **Home continuity line** — `GET /api/memory/presence?tzOffsetMinutes=` returns `{ daysReflected, windowDays, reflectedToday }`; Home shows "You've reflected N days of the last 7" under the greeting. Hidden at 0 — acknowledgment only, never guilt.

No browsable surface, no settings — memory stays invisible (invisible-content principle).
