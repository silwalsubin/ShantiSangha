# ShantiSangha Q2 2026 Product Planning

## Product Vision

ShantiSangha is a spiritual wellness companion rooted in Hindu and Buddhist wisdom. It helps people build a daily spiritual practice through guided reflection, meditation, journaling, and AI-powered conversations grounded in sacred teachings.

**Core belief:** Spiritual growth happens in small daily moments — a morning reflection, a mindful pause during stress, an evening journal entry. ShantiSangha makes these moments accessible, personal, and habitual.

**Long-term goal:** A trusted daily companion that feels like having a wise, calm guide in your pocket — one who knows your journey, remembers your struggles, and meets you where you are.

**Identity:** This is not a generic wellness app. It is a *spiritual space* — users should feel "this is my place for inner work."

---

## Current State (End of Q1)

### What's Live
- **AI Spiritual Companion** — GPT-4o conversations with streaming responses
- **Journaling** — entries with AI-generated summaries and insights
- **Mood Check-ins** — daily 1-10 scoring with notes, trend tracking
- **Coping Exercises** — 8 guided exercises (box breathing, grounding, body scan, etc.)
- **Voice Notes** — audio upload with async transcription
- **Semantic Search** — vector search across journals and insights (pgvector)
- **Saved Insights** — AI-extracted takeaways from conversations and journals
- **Auth** — Clerk production with Google SSO
- **Sacred Theme UI** — Hindu scripture-inspired design with custom sacred icons

### Infrastructure
- AWS ECS Fargate, RDS PostgreSQL 16 (pgvector), ElastiCache Redis 7
- CloudFront CDN, S3 frontend, ACM SSL for shantisangha.org
- Terraform IaC, GitHub Actions CI/CD
- Hangfire background jobs

### Known Gaps
- No onboarding flow
- No daily practice / routine system
- Chat has no memory across conversations
- No guided audio content (meditations, chants)
- No push notifications or reminders
- No data export or account deletion
- Voice entries have no playback UI
- No analytics or usage tracking
- Pages need responsive design polish

---

## Q2 Objectives (April - June 2026)

### Theme: "Build the daily practice"

Q2 transforms ShantiSangha from a collection of features into a *daily spiritual habit*. Every change should answer: "Does this make someone open the app tomorrow?"

---

### Objective 1: Personalized Spiritual Dashboard

**Why:** The dashboard should feel alive — not a static page but a daily spiritual companion that greets you with purpose.

| Initiative | Description | Priority |
|---|---|---|
| Daily teaching | Dynamic quote/verse from Gita, Dhammapada, Upanishads — rotates daily | P0 |
| Today's practice | Suggested daily practice based on mood/history (meditate, journal, breathe) | P0 |
| Practice streak | Visual streak counter for consecutive days of any practice | P1 |
| Progress summary | Meditation minutes, journal entries, mood trend — at a glance | P1 |
| Quick actions | One-tap: "How am I feeling?", "Start a reflection", "Breathe" | P0 |
| Time-aware greeting | Morning/afternoon/evening with contextual spiritual encouragement | P1 |

---

### Objective 2: AI Spiritual Companion (Deepened)

**Why:** This is the core differentiator. The AI should feel like a wise teacher who knows your journey, not a generic chatbot.

| Initiative | Description | Priority |
|---|---|---|
| Conversation memory | Include past insights, mood trends, recent journals in system prompt | P0 |
| Spiritual grounding | System prompt trained on Gita, Buddhist teachings, mindfulness wisdom | P0 |
| Contextual responses | "I feel anxious" → guided response with breathing exercise + teaching | P0 |
| Suggested prompts | 3 contextual starters based on mood/time/recent activity | P1 |
| Chat auto-titles | Generate meaningful titles from conversation content | P1 |
| Crisis detection | Detect distress, show helpline resources, gentle disclaimers | P0 |
| Reflection prompts | End-of-conversation: "What did you learn about yourself?" | P2 |

---

### Objective 3: Guided Content Library

**Why:** Content is what brings users to the app. Guided meditations and teachings give people a reason to return daily.

| Initiative | Description | Priority |
|---|---|---|
| Audio meditations | 5-10 guided meditations (breathing, body scan, loving-kindness) | P1 |
| Sacred chants | Om, Gayatri Mantra, peace mantras — with loop/timer | P1 |
| Teaching snippets | Short audio/text teachings from Gita, Dhammapada | P2 |
| Resume playback | Continue where you left off | P2 |
| Practice timer | Simple meditation timer with bell sounds | P1 |

---

### Objective 4: Onboarding & First Experience

**Why:** First 2 minutes determine if someone stays. Make them meaningful, not bureaucratic.

| Initiative | Description | Priority |
|---|---|---|
| Welcome flow | "What brings you here?" → intention setting → first practice | P0 |
| Guided first chat | Pre-seeded spiritual conversation, not empty screen | P1 |
| Empty states | Replace "No X yet" with invitations to practice | P1 |
| Onboarding checklist | Gentle nudges: set mood, try a meditation, write first journal | P2 |

---

### Objective 5: Growth & Reflection Tracking

**Why:** Make inner growth visible. People stick with what they can see progress in.

| Initiative | Description | Priority |
|---|---|---|
| Weekly reflection | Auto-generated weekly summary: mood arc, insights, practices done | P1 |
| Emotional trends | Visualize mood patterns over weeks/months | P1 |
| Journal insights | AI-tagged themes and emotional patterns across entries | P2 |
| Practice log | Track meditation minutes, journaling frequency, coping sessions | P1 |
| Monthly review | "Your month in reflection" — shareable summary | P2 |

---

### Objective 6: Mobile & UX Polish

**Why:** Spiritual moments happen on phones — commuting, before sleep, during breaks. It must feel native.

| Initiative | Description | Priority |
|---|---|---|
| Responsive redesign | Every page polished for mobile with sacred theme | P0 |
| PWA support | Manifest + service worker for "Add to Home Screen" | P1 |
| Voice playback | Audio player with waveform for voice entries | P1 |
| Loading states | Smooth transitions, not jarring skeleton screens | P2 |
| Dark mode | Evening/night theme — warm, not cold dark | P2 |

---

### Objective 7: Trust, Privacy & Operations

**Why:** Spiritual and emotional data is sacred. And we need visibility into what's working.

| Initiative | Description | Priority |
|---|---|---|
| Privacy page | Clear, warm explanation of data handling | P0 |
| Account deletion | Self-serve delete with data wipe | P0 |
| Data export | Download journals, insights, mood history | P1 |
| Terms of service | Legal copy for production | P0 |
| Error tracking | Sentry for frontend + backend | P0 |
| Usage analytics | Simple event tracking (practices started, retention) | P1 |
| Cost monitoring | AWS budget alerts | P1 |

---

## Monthly Breakdown

### April — Foundation & Daily Practice
- **Dashboard redesign** with daily teaching, today's practice, quick actions
- **Onboarding flow** — intention setting + first practice
- **AI spiritual grounding** — system prompt with teachings, conversation memory
- **Crisis detection** + safety disclaimers
- **Privacy page + terms of service + account deletion**
- **Error tracking (Sentry)**
- **Responsive redesign** of all pages

### May — Content & Depth
- **Guided audio meditations** (5-10 tracks)
- **Sacred chants** with loop/timer
- **Practice timer** for silent meditation
- **Suggested prompts** in chat
- **Weekly reflection** summaries
- **Voice playback UI**
- **PWA support**
- **Usage analytics**

### June — Habit & Growth
- **Practice streaks** visualization
- **Emotional trend** charts
- **Practice log** (minutes, frequency)
- **Daily reminders** (email/browser notification)
- **Chat auto-titles**
- **Dark mode**
- **Monthly review** feature
- **Performance optimization**

---

## Success Metrics

| Metric | Current | Q2 Target |
|---|---|---|
| Registered users | 1 | 100 |
| Weekly active users | 0 | 25 |
| Daily practice completion rate | 0 | 40% |
| Avg practices per active user/week | 0 | 4 |
| Avg conversations per active user/week | 0 | 2 |
| 7-day retention (new users) | unknown | 35% |
| 30-day retention | unknown | 20% |
| Error rate (5xx) | unknown | < 1% |
| P95 API latency | unknown | < 500ms |

---

## Future Roadmap (Post-Q2)

These are valuable but too large or premature for Q2:

### Q3 — Community & Connection
- **Sangha Circles** — small group meditation/study groups
- **Shared practices** — meditate together in real-time
- **Discussion threads** — reflect on teachings together
- **Teacher/guide profiles**

### Q4 — Expansion
- **Events & retreats** — satsangs, workshops, calendar sync
- **Seva marketplace** — volunteer opportunities, service matching
- **Multi-language** — Hindi, Sanskrit, Nepali
- **Native mobile apps** (React Native)

### Beyond
- **Therapist integration** — bridge spiritual + clinical support
- **AI fine-tuning** on sacred texts
- **Monetization** — premium content, group subscriptions
- **HIPAA compliance** for clinical partnerships

---

## Open Questions

1. Should we offer a guest mode (no sign-up) for the first guided meditation?
2. What sacred texts should the AI be grounded in? (Gita, Dhammapada, Yoga Sutras, Upanishads — all?)
3. Should audio content be user-generated eventually or always curated?
4. Weekly reflections: email, in-app, or both?
5. Dark mode: user toggle or system preference?
6. Should the practice streak reset on miss or allow "rest days"?
7. How do we handle users in genuine crisis? Hotline integration?
