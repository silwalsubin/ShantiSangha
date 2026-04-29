# AI Spiritual Companion (Chat)

## Purpose
The core feature of ShantiSangha. A conversational AI that helps users process emotions, reflect on their inner state, and receive guidance grounded in spiritual wisdom.

## Value
- Provides a private, non-judgmental space to talk through feelings
- Available 24/7 — no appointment, no waiting
- Helps users who aren't ready for therapy but need more than journaling alone

## How it works
- User creates a conversation and sends messages
- Backend streams responses via Server-Sent Events (SSE) using GPT-4o
- Messages are stored as conversation history for the user
- The companion uses current goals, today's reflection, and Jyotish context when available
- Each conversation belongs to one user, identified via JWT `sub` claim

## Key files
- Frontend: `frontend/src/pages/app/reflect/index.vue`, `frontend/src/pages/app/reflect/chat.vue`
- Backend controller: `backend/ShantiSangha.Chat/Controllers/ConversationsController.cs`
- AI service: `backend/ShantiSangha.Chat/AI/ChatService.cs`

## API endpoints
- `GET /api/conversations` — list conversations
- `POST /api/conversations` — create conversation
- `GET /api/conversations/{id}` — get conversation with messages
- `DELETE /api/conversations/{id}` — delete conversation
- `POST /api/conversations/{id}/messages` — send message (SSE streaming response)

## Q2 improvements planned
- Spiritual grounding (system prompt with Gita, Buddhist teachings)
- Contextual responses ("I feel anxious" → breathing exercise + teaching)
- Suggested prompts based on mood/time/activity
- Auto-generated conversation titles
- Crisis detection with helpline resources
