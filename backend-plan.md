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
| Hosting | AWS ECS Fargate + RDS PostgreSQL + ElastiCache Redis |
| IaC | Terraform (`infrastructure/terraform/`) |

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

### AWS (ECS Fargate)

All infrastructure is defined as code in `infrastructure/terraform/`.

| Resource | AWS Service |
|---|---|
| Container runtime | ECS Fargate |
| Container registry | ECR |
| Database | RDS PostgreSQL 16 (pgvector built-in) |
| Cache / job queue | ElastiCache Redis 7 |
| Load balancer | Application Load Balancer |
| Secrets | Secrets Manager |
| Logs | CloudWatch Logs |
| Networking | VPC with public (ECS, ALB) + private (RDS, Redis) subnets |

**Deploy flow:**
1. GitHub Actions builds Docker image, pushes to ECR with `git sha` tag
2. `aws ecs update-service --force-new-deployment` pulls latest image
3. ECS performs rolling deployment (50% min healthy)

**First-time setup:**
```bash
cd infrastructure/terraform
cp ../terraform.tfvars.example terraform.tfvars
# fill in terraform.tfvars
terraform init
terraform apply
```

### Scaling path

- Increase `desired_count` for horizontal scale
- Upgrade `db_instance_class` / `node_type` for DB scale
- Add HTTPS listener to ALB with ACM certificate
- Enable RDS Multi-AZ for high availability

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
- [x] Implement conversation CRUD endpoints
- [x] Implement message persistence
- [x] Integrate Semantic Kernel with OpenAI
- [x] Implement SSE streaming for chat responses
- [x] Build layered memory context builder (recent messages + summaries + insights)
- [x] Write system prompt and persona configuration

### Week 5: Journals, Moods, Coping
- [x] Implement journal CRUD endpoints
- [x] Implement mood check-in endpoints and trends aggregation
- [x] Implement coping exercise catalog and session logging

### Week 6: Safety Pipeline
- [x] Integrate OpenAI moderation API as request middleware
- [x] Build risk classifier for self-harm and crisis patterns
- [x] Implement safety escalation flow with support resource responses
- [x] Implement response-level safety review before delivery
- [x] Set up `safety_events` logging

### Week 7: Background Jobs
- [x] Set up Hangfire with PostgreSQL storage
- [x] Implement `GenerateSummary` job
- [x] Implement `GenerateEmbedding` job
- [x] Implement `ExtractInsights` job
- [x] Wire job dispatch from API endpoints

### Week 8: Voice
- [x] Set up Cloudflare R2 bucket
- [x] Implement presigned upload URL endpoint
- [x] Implement voice entry creation after upload
- [x] Implement `TranscribeVoice` job using Whisper API
- [x] Wire transcript back to journal draft creation

### Week 9: Semantic Search
- [x] Implement pgvector similarity search queries
- [x] Use embeddings to surface relevant past insights in chat context
- [x] Add semantic search endpoint for insights and journals

### Week 10: Observability and Deploy
- [x] Wire Langfuse for AI call tracing
- [x] Set up OpenTelemetry for request tracing
- [x] Write Dockerfile for `ShantiSangha.Api`
- [x] Write Terraform IaC for AWS (ECS Fargate, RDS, ElastiCache, ALB, ECR, Secrets Manager)
- [x] Add CI/CD workflow for backend (build + push to ECR + ECS deploy on push)
- [ ] Create AWS account and IAM deploy user, add `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` to GitHub secrets
- [ ] Run `terraform apply` to provision infrastructure
- [ ] Run EF Core migration against RDS (`dotnet ef database update`)
- [ ] Deploy and smoke test all endpoints
