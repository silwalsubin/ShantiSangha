# CLAUDE.md — Project Rules for ShantiSangha

## Features
See `docs/features/` for detailed feature documentation (purpose, value, how it works, key files, API endpoints).
- [Home](docs/features/dashboard.md) — daily landing page with reflection and practice progress
- [Reflection](docs/features/reflection.md) — AI-generated daily observation drawn from the user's real data
- [Chat](docs/features/chat.md) — AI spiritual companion (GPT-4o, SSE streaming)
- [Journal](docs/features/journal.md) — private reflection writing with AI summaries/insights
- [Goals](docs/features/goals.md) — daily intentions with streak-based discipline tracking
- [Insights](docs/features/insights.md) — AI-extracted takeaways from conversations and journals
- [Voice](docs/features/voice.md) — audio notes with async transcription
- [Friends](docs/features/friends.md) — quiet shared accountability; aggregated activity only, never content

## Design Principles
Every UI decision must honor these principles. See `docs/design-principles/` for details:
- [Simplicity](docs/design-principles/simplicity.md) — ONE experience, not modules. 3 tabs only. No bells and whistles.
- [Privacy](docs/design-principles/privacy.md) — user data is never shared. This is their sacred private space.
- [Sacred Aesthetic](docs/design-principles/sacred-aesthetic.md) — saffron/gold/parchment, no emojis, no cold colors.
- [Mobile First](docs/design-principles/mobile-first.md) — 375px minimum, 44px touch targets, design for phones.
- [One Experience](docs/design-principles/one-experience.md) — screens flow into each other, no dead ends.

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
