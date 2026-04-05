# ShantiSangha Q2 2026 Product Planning

## Product Vision

ShantiSangha is a spiritual wellness companion rooted in Hindu and Buddhist wisdom. It helps people build a daily spiritual practice through guided reflection, journaling, goal-setting, and AI-powered conversations grounded in sacred teachings.

**Core belief:** Spiritual growth happens in small daily moments — a morning intention, a mindful pause during stress, an evening journal entry. ShantiSangha makes these moments accessible, personal, and habitual.

**Long-term goal:** A trusted daily companion that feels like having a wise, calm guide in your pocket — one who knows your journey, remembers your struggles, and meets you where you are.

**Identity:** This is not a generic wellness app. It is a *spiritual space* — users should feel "this is my place for inner work."

---

## Current State (April 5, 2026)

### What's Live — Web + Native iOS

The app has evolved significantly from its Q1 state. We now have a full native iOS app with near feature-parity to the web, an offline-first architecture, and a mature goals/tasks system that has become the core daily engagement loop.

**Core Loop: Reflect → Track → Grow**

- **AI Spiritual Companion** — GPT-4o streaming conversations with safety pipeline (crisis detection, moderation, escalation)
- **Journaling** — entries with AI-generated summaries and insights
- **Voice Notes** — audio upload with async transcription (no playback UI yet)
- **Goals & Commitments** — recurring daily tasks with streaks + one-time milestones with due dates, progress tracking, deeper-why intentions, AI nudges, full activity history timeline
- **Journey Dashboard** — premium-style view with progress rings, completion rates, period filters (week/month/3 months), AI reflections
- **Coping Exercises** — 8 guided text-based exercises (box breathing, grounding, body scan, etc.)
- **Insights** — AI-extracted takeaways from conversations and journals, semantic search (pgvector)
- **Auth** — Clerk with Google SSO

**iOS Native App (SwiftUI)**
- Full 4-tab navigation: Home, Reflect, Journey, Settings
- Offline-first with SwiftData + SyncService
- Network monitoring, push notification infrastructure (not fully wired)
- Swipe gestures for task completion, haptic feedback
- Near feature-parity with web

**Infrastructure**
- AWS ECS Fargate, RDS PostgreSQL 16 (pgvector), ElastiCache Redis 7
- CloudFront CDN, S3 frontend, ACM SSL
- Terraform IaC, GitHub Actions CI/CD (frontend, backend, iOS tests)
- Hangfire background jobs

### What Changed Since Original Plan

The app's direction shifted meaningfully from the original Q2 plan:

1. **Goals/Tasks became the core loop** — instead of a generic "daily practice" system, we built a full commitment tracker with streaks, milestones, progress rings, AI nudges, and activity timelines. This is the feature that drives daily opens.
2. **iOS native app exists** — the original plan assumed web-only with PWA aspirations. We now have a full SwiftUI app, making PWA less relevant.
3. **Journey replaced simple tracking** — instead of basic mood charts, Journey became a premium dashboard with AI reflections, completion rates, and celebration of consistency.
4. **Spiritual feedback removed** — we tried inline motivational messages on tasks and removed them. The app's tone comes through the AI companion and design, not through scattered quotes.
5. **Mood check-ins deprioritized** — the daily mood scoring system didn't fit the flow. Emotional awareness comes through journaling and AI conversations instead.

---

## Q2 Revised Objectives (April - June 2026)

### Theme: "Deepen the companion, earn the habit"

The foundation is solid — people can set goals, journal, and talk to an AI companion. Now we need to make the AI *actually know you*, give people reasons to come back every morning, and build the trust layer for real users.

---

### Objective 1: AI That Knows You

**Why:** The AI companion is the core differentiator, but right now every conversation starts cold. A spiritual guide who forgets everything isn't a guide — it's a search engine.

| Initiative | Description | Priority |
|---|---|---|
| Conversation memory | Include past insights, mood patterns, recent journals, and goals in the system prompt | P0 |
| Spiritual grounding | System prompt grounded in Gita, Dhammapada, Buddhist teachings — not generic wellness advice | P0 |
| Contextual responses | "I feel anxious" → guided response with breathing exercise link + relevant teaching | P1 |
| Suggested prompts | 3 contextual conversation starters based on recent activity/time of day | P1 |
| Chat auto-titles | Generate meaningful titles from conversation content | P2 |

*Crisis detection and moderation are already live.*

---

### Objective 2: The Morning Open

**Why:** The dashboard needs to give people a reason to open the app every morning. Right now it shows tasks — useful but not inspiring. It should feel like a daily spiritual greeting.

| Initiative | Description | Priority |
|---|---|---|
| Daily verse | Rotating quote/verse from Gita, Dhammapada, Upanishads — changes daily | P0 |
| Time-aware greeting | Morning/afternoon/evening with contextual encouragement | P1 |
| Today's reflection prompt | One thought-provoking question to carry through the day | P1 |
| Quick actions polish | One-tap access to journal, chat, breathe from the dashboard | P1 |

*Practice streaks, progress rings, and task management are already live on the dashboard.*

---

### Objective 3: Notifications & Reminders

**Why:** The iOS notification infrastructure exists but isn't wired. Without reminders, the app relies entirely on the user remembering to open it. That's not how habits form.

| Initiative | Description | Priority |
|---|---|---|
| Daily reminder | Configurable morning notification — "Your practice awaits" | P0 |
| Smart nudges | Missed 2+ days? Gentle re-engagement nudge | P1 |
| Evening reflection | Optional end-of-day prompt — "How did today go?" | P2 |

*iOS NotificationService and Settings toggle already exist — this is about wiring them up properly.*

---

### Objective 4: Trust & Privacy

**Why:** People are writing about their deepest fears, spiritual doubts, and emotional struggles. They need to *know* their data is safe before they'll truly open up. This is table stakes for real users.

| Initiative | Description | Priority |
|---|---|---|
| Account deletion | Self-serve delete with full data wipe | P0 |
| Privacy page | In-app, warm explanation of data handling — not legalese | P0 |
| Terms of service | Required for App Store submission | P0 |
| Data export | Download journals, insights, conversation history | P1 |
| Error tracking | Sentry integration for frontend + backend + iOS | P1 |

---

### Objective 5: Onboarding

**Why:** First 2 minutes determine if someone stays. Right now a new user sees empty lists. That's a dead end.

| Initiative | Description | Priority |
|---|---|---|
| Welcome flow | "What brings you here?" → set first intention → guided first action | P0 |
| Guided first chat | Pre-seeded conversation that feels like meeting your guide | P1 |
| Empty states | Replace "No X yet" with invitations to practice | P1 |

---

### Objective 6: iOS App Store Readiness

**Why:** The iOS app is functionally complete but not shippable. Getting it into TestFlight and then the App Store unlocks real distribution.

| Initiative | Description | Priority |
|---|---|---|
| App Store metadata | Screenshots, description, privacy labels | P0 |
| TestFlight beta | Internal testing with real devices | P0 |
| Notification wiring | Connect iOS notification infrastructure to backend scheduling | P1 |
| Voice playback | Audio player for voice entries in iOS | P2 |

---

## Monthly Breakdown

### April — AI Memory & Morning Experience
- **Conversation memory** — include user context in AI system prompt
- **Spiritual grounding** — sacred text-informed system prompt
- **Daily verse** on dashboard
- **Time-aware greeting**
- **Privacy page + terms of service** (needed for App Store)

### May — Onboarding, Notifications & Trust
- **Welcome flow** for new users
- **Guided first chat** experience
- **Daily reminder notifications** (iOS + web)
- **Account deletion** endpoint + UI
- **Data export**
- **Sentry integration**
- **TestFlight beta** release

### June — Polish, Submit & Grow
- **Suggested prompts** in chat
- **Chat auto-titles**
- **Smart nudges** for re-engagement
- **Empty state improvements**
- **App Store submission**
- **Performance optimization** and bug sweep

---

## What We're NOT Doing in Q2

These were in the original plan but are cut or deferred:

| Cut | Why |
|---|---|
| Guided audio meditations & chants | Large content investment with uncertain engagement. Revisit after validating daily usage with current features. |
| Practice timer | Coping exercises serve this need adequately for now. |
| PWA support | We have a native iOS app. PWA adds complexity without clear value. |
| Dark mode | Nice-to-have but won't drive retention. The sacred warm aesthetic is core to the identity. |
| Weekly/monthly email summaries | Build in-app first. Journey dashboard partially serves this need. |
| Emotional trend charts | Journey dashboard with AI reflections replaced the need for raw mood charts. |
| Usage analytics | Defer until we have real users to measure. |

---

## Success Metrics

| Metric | Current | Q2 Target |
|---|---|---|
| TestFlight testers | 0 | 10-20 |
| App Store submission | No | Yes |
| Weekly active users (web + iOS) | 1 | 20 |
| Daily task completion rate | N/A | 40% |
| Avg conversations per active user/week | N/A | 2 |
| 7-day retention (new users) | unknown | 30% |
| Error rate (5xx) | unknown | < 1% |
| P95 API latency | unknown | < 500ms |
| Account deletion available | No | Yes |

---

## Future Roadmap (Post-Q2)

### Q3 — Content & Depth
- **Guided audio meditations** — 5-10 tracks (breathing, body scan, loving-kindness)
- **Sacred chants** with loop/timer (Om, Gayatri Mantra)
- **Dark mode** — warm evening theme
- **Weekly reflection summaries** — AI-generated weekly review
- **Voice playback UI** with waveform

### Q4 — Community & Connection
- **Sangha Circles** — small group meditation or study groups
- **Shared practices** — meditate together
- **Multi-language** — Hindi, Nepali
- **Android app** consideration

### Beyond
- **AI fine-tuning** on sacred texts
- **Therapist integration** — bridge spiritual + clinical support
- **Monetization** — premium content, group subscriptions
- **Events & retreats** — satsangs, workshops

---

## Open Questions

1. Should the AI companion have distinct "personalities" or teaching lineages the user can choose?
2. How deeply should conversation memory go? Last 5 conversations? All-time summary?
3. What sacred texts should the AI draw from? (Gita, Dhammapada, Yoga Sutras, Upanishads — all?)
4. For App Store review: how do we position the AI spiritual advice vs. "not a substitute for professional help"?
5. Should we gate features behind onboarding completion or let people explore freely?
6. Android: React Native, Kotlin native, or defer entirely?
