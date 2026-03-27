# ShantiSangha Q2 2026 Product Planning

## Product Vision

ShantiSangha is a wellness companion for emotional support, reflection, and everyday mental well-being. It helps people process what they are feeling, build self-awareness, and find a private, steady place for emotional grounding.

**Core belief:** Many people need support before they ever ask for help. ShantiSangha exists for the in-between moments — when someone feels overwhelmed, isolated, anxious, or mentally tired and wants a grounded place to reflect without pressure or judgment.

**Long-term goal:** A trusted, calm, human-feeling product that helps people feel less alone, more self-aware, and more supported in their daily lives.

---

## Current State (End of Q1)

### What's Live
- **AI Chat** — GPT-4o powered conversations with streaming responses
- **Journaling** — create, edit, delete entries with AI-generated summaries and insights
- **Mood Check-ins** — daily 1-10 scoring with notes, trend tracking, daily averages
- **Coping Exercises** — 8 guided exercises (box breathing, grounding, body scan, etc.) with session logging
- **Voice Notes** — audio upload via presigned S3 URLs with async transcription
- **Semantic Search** — vector search across journals and insights using pgvector
- **Saved Insights** — AI-extracted takeaways from conversations and journals
- **Auth** — Clerk production with Google SSO, email/password

### Infrastructure
- AWS ECS Fargate, RDS PostgreSQL 16 (pgvector), ElastiCache Redis 7
- CloudFront CDN with S3 frontend hosting, ACM SSL for shantisangha.org
- Terraform IaC, GitHub Actions CI/CD (backend, frontend, infrastructure)
- Hangfire background jobs for summaries, embeddings, insights, transcription

### Known Gaps
- No onboarding flow for new users
- No push notifications or reminders
- Chat lacks memory of previous conversations
- No data export or account deletion self-serve
- Voice transcription has no playback UI
- Mobile experience is functional but not optimized
- No analytics or usage tracking
- Clerk webhook not configured (users auto-created on first API call)

---

## Q2 Objectives (April - June 2026)

### Theme: "Make it worth returning to"

The core features exist. Q2 is about making them feel polished, personal, and habitual — so that someone who tries ShantiSangha once wants to come back.

---

### Objective 1: Onboarding & First Experience

**Why:** New users land on the dashboard with no context. The first 2 minutes determine retention.

| Initiative | Description | Priority |
|---|---|---|
| Welcome flow | 3-step onboarding: name, what brought you here, first mood check-in | P0 |
| Guided first chat | Pre-seeded conversation starter instead of empty chat | P1 |
| Empty states | Replace "No X yet" with actionable prompts on every page | P1 |
| Tooltip tour | Subtle highlights of key features on first visit | P2 |

---

### Objective 2: Conversation Quality & Memory

**Why:** The AI chat is the core value prop. It needs to feel like it knows you over time.

| Initiative | Description | Priority |
|---|---|---|
| Conversation context | Include relevant past insights/mood in system prompt | P0 |
| Chat titles | Auto-generate meaningful titles from first few messages | P1 |
| Suggested prompts | Show 3 contextual conversation starters based on recent mood/journals | P1 |
| Safety improvements | Better crisis detection, resource links, disclaimer copy | P0 |
| Conversation summary | End-of-conversation summary shown in chat list | P2 |

---

### Objective 3: Habit & Engagement

**Why:** Wellness tools only work with consistent use. Make it easy to build a daily rhythm.

| Initiative | Description | Priority |
|---|---|---|
| Daily check-in reminder | Email or browser notification at user-chosen time | P1 |
| Streak tracking | Visual streak counter for consecutive check-in days | P2 |
| Weekly reflection | Auto-generated weekly summary email of mood trends + insights | P1 |
| Quick actions | Dashboard shortcuts: "How are you?", "Journal a thought", "Breathe" | P1 |

---

### Objective 4: Mobile & UX Polish

**Why:** Most emotional moments happen on phones. The mobile experience must feel native.

| Initiative | Description | Priority |
|---|---|---|
| Responsive refinement | Fix spacing, touch targets, bottom nav overlap on small screens | P0 |
| PWA support | Add manifest + service worker for "Add to Home Screen" | P1 |
| Dark mode | Evening/night theme for bedtime journaling | P2 |
| Loading states | Replace skeleton placeholders with smoother transitions | P2 |
| Voice playback | Audio player for voice entries with waveform | P1 |

---

### Objective 5: Trust & Privacy

**Why:** Emotional data is deeply personal. Users need to feel safe.

| Initiative | Description | Priority |
|---|---|---|
| Privacy page | Clear explanation of what data is stored and how | P0 |
| Data export | Download all your data as JSON/PDF | P1 |
| Account deletion | Self-serve account + data deletion | P0 |
| Session management | Show active sessions, ability to sign out everywhere | P2 |
| Terms of service | Legal copy for production launch | P0 |

---

### Objective 6: Observability & Operations

**Why:** Can't improve what you can't measure. Need visibility into usage and errors.

| Initiative | Description | Priority |
|---|---|---|
| Error tracking | Sentry or similar for frontend + backend exceptions | P0 |
| Usage analytics | Simple event tracking (conversations started, check-ins, etc.) | P1 |
| Health dashboard | CloudWatch alarms for ECS, RDS, error rates | P1 |
| Clerk webhook | Configure webhook for user sync, handle user.deleted | P2 |
| Cost monitoring | AWS budget alerts, right-size infrastructure | P1 |

---

## Monthly Breakdown

### April — Foundation
- Welcome flow + onboarding
- Safety improvements (crisis detection, disclaimers)
- Privacy page + terms of service
- Account deletion
- Error tracking (Sentry)
- Responsive fixes
- Clerk webhook setup

### May — Depth
- Conversation context (memory across chats)
- Suggested prompts
- Weekly reflection emails
- Data export
- PWA support
- Voice playback UI
- Usage analytics

### June — Habit
- Daily reminders
- Quick actions on dashboard
- Streak tracking
- Chat auto-titles
- Dark mode
- CloudWatch alarms + cost monitoring
- Performance optimization

---

## Success Metrics

| Metric | Current | Q2 Target |
|---|---|---|
| Registered users | 1 | 50 |
| Weekly active users | 0 | 15 |
| Avg check-ins per active user/week | 0 | 3 |
| Avg conversations per active user/week | 0 | 2 |
| 7-day retention (new users) | unknown | 30% |
| Error rate (5xx) | unknown | < 1% |
| P95 API latency | unknown | < 500ms |

---

## Out of Scope for Q2

- Native mobile apps (iOS/Android)
- Multi-language support
- Therapist/professional integration
- Social features or community
- Monetization or paid plans
- AI model fine-tuning
- HIPAA compliance

---

## Open Questions

1. Should we offer anonymous/guest mode (no sign-up) for first conversation?
2. What is the right cadence for weekly reflections — email vs in-app?
3. Do we need a content moderation policy for journals?
4. When should we start thinking about a custom domain for email (noreply@shantisangha.org)?
5. Should dark mode be user-toggled or follow system preference?
