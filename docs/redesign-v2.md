# ShantiSangha V2 Redesign — Simplicity First

## Problem

The current UI has 7 nav tabs (Dashboard, Chat, Journal, Mood, Coping, Insights, Voice) that feel like separate modules glued together. Users must learn 7 different mental models. Nothing flows naturally from one action to the next.

A spiritual wellness app should feel like **one calm, continuous experience** — not an enterprise dashboard.

## Design Principle

**One path, not seven doors.**

The user opens the app, grounds themselves, reflects, and sees their growth. That's the entire experience. Everything else is a tool within that flow, not a separate destination.

---

## New Information Architecture

### 3 tabs instead of 7

```
┌──────────┐  ┌──────────┐  ┌──────────┐
│   Home   │  │  Reflect  │  │  Journey  │
│          │  │           │  │           │
│  Ground  │  │  Process  │  │   Grow    │
│ yourself │  │  what you │  │  through  │
│  today   │  │   feel    │  │   time    │
└──────────┘  └──────────┘  └──────────┘
```

---

## Tab 1: Home

**Purpose:** Ground yourself today. This is what you see when you open the app.

**Layout (single scroll):**

```
┌─────────────────────────────┐
│  🪷  ShantiSangha           │
│                             │
│  Good morning, Subin        │
│                             │
│  ┌───────────────────────┐  │
│  │  Daily Verse           │  │
│  │  "You have the right   │  │
│  │  to work, but never    │  │
│  │  to the fruit of work" │  │
│  │  — Bhagavad Gita 2.47  │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  How are you feeling?  │  │
│  │  ○○○○●○○○○○  (5/10)   │  │
│  │  [Save Check-in]       │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Today's Practice      │  │
│  │  Based on your mood:   │  │
│  │  "Try 3 minutes of     │  │
│  │   mindful breathing"   │  │
│  │  [Start Practice]      │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Continue reflecting   │  │
│  │  → Last conversation   │  │
│  │  → Recent journal      │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**What merges here:**
- Dashboard (greeting, mood check-in, recent activity)
- Coping exercises (as "Today's Practice" — one suggested exercise, not a catalog)

---

## Tab 2: Reflect

**Purpose:** Process what you feel. One unified space for all reflection.

**Layout:**

```
┌─────────────────────────────┐
│  Reflect                    │
│                             │
│  How would you like to      │
│  reflect today?             │
│                             │
│  ┌───────────────────────┐  │
│  │  💬 Talk               │  │
│  │  Have a conversation   │  │
│  │  with your companion   │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  ✍️ Write              │  │
│  │  Journal your          │  │
│  │  thoughts              │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  🎙️ Speak             │  │
│  │  Record a voice note   │  │
│  └───────────────────────┘  │
│                             │
│  ─── Recent reflections ─── │
│                             │
│  ┌───────────────────────┐  │
│  │  Conversation · 2h ago │  │
│  │  "I talked about..."   │  │
│  ├───────────────────────┤  │
│  │  Journal · Yesterday   │  │
│  │  "Feeling calmer..."   │  │
│  ├───────────────────────┤  │
│  │  Voice · 3 days ago    │  │
│  │  "2:34 · Transcribed"  │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**What merges here:**
- Chat (conversations list + new conversation)
- Journal (entries list + new entry)
- Voice (recordings list + new recording)

**Sub-pages (navigate into from here):**
- `/app/reflect/chat/:id` — active conversation
- `/app/reflect/journal/:id` — view/edit journal entry
- `/app/reflect/journal/new` — new journal entry
- `/app/reflect/voice/:id` — voice entry with playback

**Key idea:** All three reflection modes live together. The "Recent reflections" list is a **unified timeline** showing conversations, journals, and voice entries mixed together, sorted by date.

---

## Tab 3: Journey

**Purpose:** See your growth over time. Patterns, insights, and progress.

**Layout:**

```
┌─────────────────────────────┐
│  Your Journey               │
│                             │
│  ┌───────────────────────┐  │
│  │  Mood Over Time        │  │
│  │  ▁▂▃▅▆▅▇█▆▅           │  │
│  │  Avg: 6.2  ↑ Improving │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Practice Streak       │  │
│  │  🔥 7 days             │  │
│  │  (any practice counts) │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Insights              │  │
│  │  "You noticed anxiety  │  │
│  │   peaks on Sundays"    │  │
│  │  "Breathing exercises  │  │
│  │   help when stressed"  │  │
│  │  [View all →]          │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Practice History      │  │
│  │  12 conversations      │  │
│  │  8 journal entries     │  │
│  │  3 voice notes         │  │
│  │  45 min coping         │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │  Mood History          │  │
│  │  [expandable list]     │  │
│  └───────────────────────┘  │
│                             │
└─────────────────────────────┘
```

**What merges here:**
- Mood (trends, history, chart)
- Insights (saved takeaways, search)
- Coping sessions (practice history and stats)

---

## Navigation

### Mobile (bottom tabs)
```
┌────────┬────────┬────────┐
│  Home  │Reflect │Journey │
│   🪷   │   ☸    │   🪔   │
└────────┴────────┴────────┘
```

3 icons using SacredIcons:
- **Home:** `lotus`
- **Reflect:** `dialogue`
- **Journey:** `diya`

### Desktop (sidebar)
Same 3 items, vertical. The sidebar becomes much simpler — logo, 3 nav items, user button, quote.

---

## Route Structure

```
/app
  /home                    → Home (daily grounding)
  /reflect                 → Reflect hub (choose mode + timeline)
  /reflect/chat/:id        → Active conversation
  /reflect/journal/new     → New journal entry
  /reflect/journal/:id     → View/edit journal
  /reflect/voice/:id       → Voice entry detail
  /journey                 → Journey (growth + insights)
  /journey/insights        → Full insights list with search
  /journey/mood            → Detailed mood history
```

Default: `/` redirects to `/app/home`

---

## What changes in the backend?

**Nothing.** All existing API endpoints stay the same. This is purely a frontend restructure. The data model doesn't change — we're just presenting the same data differently.

The only new API we might want:
- `GET /api/timeline?limit=10` — returns a mixed list of recent conversations, journals, and voice entries sorted by date (for the "Recent reflections" unified list in the Reflect tab)

---

## Migration Path

1. **Phase 1:** Restructure routes and create the 3 new tab pages
2. **Phase 2:** Build the Reflect hub with unified timeline
3. **Phase 3:** Build the Journey page with mood/insights/practice stats
4. **Phase 4:** Remove old pages, clean up unused routes
5. **Phase 5:** Polish transitions, empty states, responsive details

---

## What we're NOT changing

- The sacred scripture theme (colors, icons, typography)
- The chat conversation UI (bubbles, streaming, input)
- The journal writing experience
- The voice recording flow
- The coping exercise timer modal
- Any backend logic

---

## Success Criteria

- A new user understands the entire app in under 30 seconds
- 3 taps maximum to start any reflection activity
- The app feels like ONE experience, not seven
- Mobile and desktop feel equally natural
- Everything still works — no features removed, just reorganized

---

## Open Questions

1. Should "Today's Practice" be AI-suggested based on mood, or a simple rotation?
2. Should the Reflect timeline show insights inline, or keep them in Journey only?
3. Do we need a separate coping exercise browser, or is one daily suggestion enough?
4. Should the mood check-in be dismissible after completing, or always visible as a summary?
5. Should we add a "quick reflect" button on Home that starts a chat immediately?
