# CLAUDE.md — Project Rules for ShantiSangha

## Features
See `docs/features/` for detailed feature documentation (purpose, value, how it works, key files, API endpoints).
- [Dashboard](docs/features/dashboard.md) — daily landing page with verse, mood check-in, quick actions
- [Chat](docs/features/chat.md) — AI spiritual companion (GPT-4o, SSE streaming)
- [Journal](docs/features/journal.md) — private reflection writing with AI summaries/insights
- [Mood](docs/features/mood.md) — daily emotional tracking with trends
- [Coping](docs/features/coping.md) — guided breathing/grounding exercises with timer
- [Insights](docs/features/insights.md) — AI-extracted takeaways from conversations and journals
- [Voice](docs/features/voice.md) — audio notes with async transcription

## Design System
See [docs/design-system.md](docs/design-system.md) for the full sacred scripture theme specification (colors, icons, typography, components, mobile rules).

**Key rules (always enforced):**
- Hindu scripture-inspired aesthetic — saffron/gold/parchment palette
- NEVER use emojis as UI icons — use `SacredIcons.vue` only
- NEVER use blue, green, or cold/tech-feeling colors
- Mobile-first: 375px minimum, 44px touch targets
- All UI changes MUST follow the design system

## Tech Stack
- **Frontend:** Vite + Vue 3 + TypeScript + Tailwind CSS v3 + Clerk auth
- **Backend:** ASP.NET Core .NET 8 + EF Core + PostgreSQL (pgvector) + Redis + Hangfire
- **Infrastructure:** AWS (ECS Fargate, RDS, ElastiCache, S3, CloudFront) + Terraform
- **CI/CD:** GitHub Actions (backend-deploy, frontend-deploy, terraform)

## API
- All API routes are under `/api` prefix
- Frontend calls `/api/*` (same origin via CloudFront)
- Auth: Clerk JWT with `MapInboundClaims = false` to preserve `sub` claim
- User resolution: `ICurrentUser` scoped service (auto-creates on first call)

## Deployment
- Push to `main` auto-triggers deploys (backend if `backend/**` changes, frontend if `frontend/**` changes)
- Terraform changes require manual `apply` via workflow dispatch
- Backend Deploy uses latest ECR image + latest task definition revision
- Frontend Deploy builds with `VITE_API_BASE_URL=/api`, syncs to S3, invalidates CloudFront
