# ShantiSangha Backend Plan

## Stack Decision

The backend is built with **ASP.NET Core** (C#). It is hosted as a Docker container on **Railway** initially, with a clear migration path to **Azure** as the product scales.

### Why ASP.NET Core

- Familiar language — faster to ship
- Top-tier performance (benchmarks alongside Go and Rust)
- Excellent ecosystem for all required layers: ORM, auth, AI, jobs, caching
- Natural upgrade path to Azure for compliance and enterprise scale

---

## Tech Stack

| Layer | Choice |
|---|---|
| API Framework | ASP.NET Core (Minimal APIs) |
| ORM | Entity Framework Core |
| Database | PostgreSQL + pgvector (via Npgsql) |
| Auth | Clerk (JWT validation middleware) |
| AI | Semantic Kernel (OpenAI backend) |
| Background Jobs | Hangfire |
| Caching | Redis via StackExchange.Redis |
| Storage | Cloudflare R2 (S3-compatible) |
| Logging | Serilog (structured JSON) |
| AI Observability | Langfuse (HTTP API) |
| App Observability | OpenTelemetry |
| Hosting (MVP) | Railway (managed Postgres + Redis) |
| Hosting (Growth) | Azure Container Apps + Azure Database for PostgreSQL |

---

## Project Structure

```
backend/
├── ShantiSangha.Api/
│   ├── Routes/
│   ├── Middleware/
│   └── Program.cs
├── ShantiSangha.Core/
│   ├── Services/
│   └── Models/
├── ShantiSangha.Infrastructure/
│   ├── Data/
│   │   ├── AppDbContext.cs
│   │   └── Migrations/
│   ├── Jobs/
│   └── AI/
└── ShantiSangha.sln
```

---

## Database Schema

### Tables

| Table | Purpose |
|---|---|
| `users` | Clerk user sync |
| `profiles` | Onboarding data and preferences |
| `conversations` | Chat sessions |
| `messages` | Per-message content and role |
| `journals` | Journal entries |
| `mood_checkins` | Mood score and notes |
| `coping_sessions` | Exercise completions |
| `saved_insights` | User-saved reflections |
| `summaries` | AI-generated summaries |
| `safety_events` | Distress detection logs |
| `voice_entries` | R2 key + transcript + processing status |

`messages`, `journals`, and `saved_insights` include a `vector(1536)` column for semantic search via pgvector.

---

## API Routes

### Auth / Users
```
POST /webhooks/clerk
GET  /me
PATCH /me
```

### Conversations
```
POST /conversations
GET  /conversations
GET  /conversations/:id
POST /conversations/:id/messages    (streams AI response via SSE)
DELETE /conversations/:id
```

### Journals
```
POST /journals
GET  /journals
GET  /journals/:id
PATCH /journals/:id
DELETE /journals/:id
```

### Mood Check-ins
```
POST /moods
GET  /moods
GET  /moods/trends
```

### Coping Exercises
```
GET  /exercises
POST /exercises/:id/sessions
GET  /exercises/sessions
```

### Saved Insights
```
POST /insights
GET  /insights
DELETE /insights/:id
```

### Voice
```
POST /voice/upload-url
POST /voice/entries
GET  /voice/entries
```

---

## AI Layer

### Chat Flow (per message)

1. Receive user message
2. Run OpenAI moderation API
3. If flagged — trigger safety flow, return support resources, log safety event
4. Build context from layered memory:
   - Recent messages
   - Conversation summaries
   - Saved insights
   - Mood trends
   - User profile/preferences
5. Call OpenAI via Semantic Kernel with system prompt + context
6. Stream response to client via SSE
7. Persist both messages asynchronously
8. Enqueue background jobs (summary generation, embedding, insight extraction)

### System Prompt Responsibilities

- Calm, supportive, non-clinical persona
- Explicit product boundaries (not a therapist)
- Crisis/distress escalation instructions
- User context injection

---

## Safety Pipeline

Every chat message passes through this middleware chain:

```
message → moderation API → risk classifier → policy check → AI response → response review → deliver or escalate
```

- Crisis keywords bypass AI entirely and return curated support resources
- All safety events are logged to `safety_events` with full context
- AI response is scanned before delivery
- Safety enforcement lives outside the model — never rely on the model alone

---

## Background Jobs (Hangfire)

| Job | Trigger | Task |
|---|---|---|
| `GenerateSummary` | Conversation ends / journal saved | AI summary → store → update embedding |
| `ExtractInsights` | After summary | Extract key insights, offer to save |
| `TranscribeVoice` | Voice upload complete | Whisper transcription → create journal draft |
| `GenerateEmbedding` | New message or journal | Compute and store vector embedding |

---

## Deployment

### MVP: Railway

- Deploy Docker container from `ShantiSangha.Api`
- Railway-managed PostgreSQL and Redis
- Environment variables for secrets
- Deploy via git push or `railway up`

### Growth: Azure

- Azure Container Apps (autoscaling, managed ingress)
- Azure Database for PostgreSQL (pgvector supported)
- Azure Cache for Redis
- Azure Blob Storage (R2-compatible migration)
- Azure OpenAI Service (optional for compliance)

---

## Delivery Checklist

### Week 1–2: Foundation
- [x] Create `backend/` directory and solution scaffold
- [x] Set up ASP.NET Core Minimal API project
- [x] Configure EF Core with Npgsql + pgvector
- [ ] Write initial DB migration and run against local Postgres
- [x] Integrate Clerk JWT validation middleware
- [x] Set up Serilog structured logging
- [x] Create Clerk webhook endpoint (`POST /webhooks/clerk`) to sync users
- [x] Wire environment config with validation

### Week 3–4: Conversations and Chat
- [ ] Implement conversation CRUD endpoints
- [ ] Implement message persistence
- [ ] Integrate Semantic Kernel with OpenAI
- [ ] Implement SSE streaming for chat responses
- [ ] Build layered memory context builder (recent messages + summaries + insights)
- [ ] Write system prompt and persona configuration

### Week 5: Journals, Moods, Coping
- [ ] Implement journal CRUD endpoints
- [ ] Implement mood check-in endpoints and trends aggregation
- [ ] Implement coping exercise catalog and session logging

### Week 6: Safety Pipeline
- [ ] Integrate OpenAI moderation API as request middleware
- [ ] Build risk classifier for self-harm and crisis patterns
- [ ] Implement safety escalation flow with support resource responses
- [ ] Implement response-level safety review before delivery
- [ ] Set up `safety_events` logging

### Week 7: Background Jobs
- [ ] Set up Hangfire with PostgreSQL storage
- [ ] Implement `GenerateSummary` job
- [ ] Implement `GenerateEmbedding` job
- [ ] Implement `ExtractInsights` job
- [ ] Wire job dispatch from API endpoints

### Week 8: Voice
- [ ] Set up Cloudflare R2 bucket
- [ ] Implement presigned upload URL endpoint
- [ ] Implement voice entry creation after upload
- [ ] Implement `TranscribeVoice` job using Whisper API
- [ ] Wire transcript back to journal draft creation

### Week 9: Semantic Search
- [ ] Implement pgvector similarity search queries
- [ ] Use embeddings to surface relevant past insights in chat context
- [ ] Add semantic search endpoint for insights and journals

### Week 10: Observability and Deploy
- [ ] Wire Langfuse for AI call tracing
- [ ] Set up OpenTelemetry for request tracing
- [ ] Write Dockerfile for `ShantiSangha.Api`
- [ ] Configure Railway project with managed Postgres and Redis
- [ ] Set up environment variables and secrets
- [ ] Deploy and smoke test all endpoints
- [ ] Add CI/CD workflow for backend (build + deploy on push)
