# Week-2 Drop-off: Diagnosis and Concrete Fixes

## Why Week 2 Is the Kill Zone

Week 1 is novelty. The user sets up goals, gets their first reflections, maybe journals once or twice. Everything feels new. By week 2, the novelty is gone and the app has to earn its place through genuine behavioral pull. Right now, it does not.

I audited the actual codebase. Here is what I found.

---

## The Core Problem: The App Doesn't Get Smarter Fast Enough

The product-guardian skill defines four hooks that drive daily return: The Mirror, The Streak, The Unfinished Thread, and The Surprise. At week 2, here is the honest state of each:

**The Mirror (Daily Reflection):** Working, but one-dimensional. The reflection prompt in `GenerateDailyReflectionJob.cs` draws from goals, streaks, conversation summaries, journal summaries, and insights. This is good context. But it never plants seeds for tomorrow. There are zero cliffhangers, zero slow reveals, zero callbacks to earlier entries. The reflection is a standalone observation every day — no narrative thread connects day 8 to day 9. By week 2, the user has read 14 reflections that feel like variations of the same thing: "you showed up, here's what I noticed." That is not enough to create "what will it say tomorrow?" curiosity.

**The Streak:** Present but brittle. There is no grace day mechanic anywhere in the backend — a search for "grace" and "streak break" returned zero results. A user who misses one day in week 2 loses their streak entirely. That is the single fastest way to lose someone. The loss aversion that should keep them coming back instead punishes them for being human, and they quit.

**The Unfinished Thread:** Non-existent. The AI companion never ends a conversation with a forward-looking question. Journal entries don't create "come back to this" threads. There is nothing in progress pulling the user back. When they close the app, nothing is unfinished.

**The Surprise:** Weak. Insights exist but are static — they sit on the Journey tab waiting to be discovered. They don't surface at unexpected moments. The reflection never references something from weeks ago (no callback mechanic). The Journey tab shows consistency percentages and practice rings, but nothing that reframes how the user sees themselves.

---

## The 5 Fixes, Ranked by Impact

### 1. Add Grace Days to Streaks (Highest Impact, Moderate Effort)

**The problem:** A user at day 10 who misses one day loses everything. They don't come back.

**The fix:** Allow one grace day per streak (no purchase, no gamification). If a user misses exactly one day, the streak is preserved but the grace is consumed. The check-in history shows the gap honestly — no pretending it didn't happen. The reflection the next day acknowledges it naturally: "You missed yesterday. The streak held. That's what grace is for."

**What changes:**
- Backend: streak calculation logic in the goal/check-in service needs a `graceDaysUsed` field and logic to preserve streaks across a single-day gap
- `GenerateDailyReflectionJob.cs`: add context about grace day usage so the reflection can reference it
- iOS `TaskRow.swift` / `GoalCalendarView.swift`: show the gap day distinctly (lighter color, not a break)

**Why this is first:** Streak death is the most concrete, most preventable reason someone leaves at week 2. Every other fix is moot if the user's streak broke on day 9 and they never came back.

---

### 2. Add Narrative Threading to Daily Reflections (Highest Impact, Moderate Effort)

**The problem:** Each reflection is an island. Day 12 has no relationship to day 11. There is no reason to come back tomorrow specifically.

**The fix:** Modify the reflection prompt to support three modes, distributed roughly:
- **70% Regular observations** (what exists today — warm, specific, grounding)
- **20% Seed-planting** ("There's a pattern forming between your journaling and your meditation timing. It's not clear yet.") — creates a pull to return tomorrow
- **10% Callbacks** ("Remember the journal entry from last Tuesday? Look at your streak since then.") — creates the feeling the app remembers your story

**What changes:**
- `GenerateDailyReflectionJob.cs`: expand the system prompt to include seed-planting and callback instructions. Add a `reflectionMode` selection (weighted random or based on day count — e.g., first callback at day 7+, first seed at day 4+). Pull older reflections and journal entries as callback candidates.
- Store a `reflectionType` field on `DailyReflection` so the next day's job knows if it needs to follow up on a seed.

**Why this is second:** The reflection is the primary reason to open the app. If it doesn't create forward pull, the user has no curiosity about tomorrow. This is the Cliffhanger Engine from the skill, and none of it is implemented.

---

### 3. Surface an Unexpected Insight on Home (High Impact, Low Effort)

**The problem:** Insights exist on the Journey tab. The user has to navigate there and look for them. Most week-2 users have never opened Journey.

**The fix:** When a new insight is extracted (from a conversation or journal), surface it once on the Home tab the next time the user opens the app — below the reflection, as a quiet "the app noticed something" card. One insight, not a feed. It appears once, then moves to Journey. If no new insight exists, nothing shows.

**What changes:**
- Backend: add an `unsurfaced` flag to insights, or a `surfacedAt` timestamp
- `HomeView.swift`: fetch the latest unsurfaced insight via a new endpoint (`GET /api/insights/latest-unsurfaced`) and render it as a simple card below the reflection
- Mark it as surfaced when the user sees it

**Why this matters at week 2:** By day 8-14, the user has enough journal/chat data for insights to start appearing. But if they never see them, the "app getting smarter" investment loop never kicks in. Bringing one insight to them — without them asking — creates the "this app knows me" moment that the skill document identifies as the core of retention.

---

### 4. Add Identity Reflection at Day 14 (Moderate Impact, Low Effort)

**The problem:** The reflection treats day 1 and day 14 identically. There is no acknowledgment that two weeks of consistency is meaningful.

**The fix:** When a user crosses the 14-day mark on any practice, the reflection prompt receives a specific flag. The reflection shifts from observation to identity: "Two weeks of daily meditation. That's not a streak anymore. That's a rhythm you chose." This is the identity attachment mechanic from the skill — and it lands precisely at the week-2 danger zone.

**What changes:**
- `GenerateDailyReflectionJob.cs`: the milestone detection already exists (lines 51-74) but only fires at exact thresholds (7, 14, 30...). Add specific prompt language for the 14-day milestone that uses identity framing rather than just acknowledgment.

**Why this matters:** The user who is about to drop off at week 2 needs to hear that what they have built matters. Not "congrats on 14 days" — that is gamification. "This is who you are now" — that is identity. It raises the cost of leaving.

---

### 5. End AI Conversations with a Forward Thread (Moderate Impact, Low Effort)

**The problem:** When the user finishes a chat with the AI companion, the conversation just... ends. There is no pull back.

**The fix:** The AI companion's system prompt should include an instruction: when a conversation reaches a natural conclusion, end with a reflective question or observation that doesn't demand an immediate answer — something the user will think about later. "That's worth sitting with. See what comes up tomorrow." This creates the Zeigarnik effect — an open loop the user carries with them.

**What changes:**
- The chat system prompt (wherever the AI companion prompt lives) gets a closing-behavior instruction
- No backend changes, no UI changes — purely prompt engineering

**Why this matters:** Right now, every conversation is complete when the user closes the chat. Nothing is unfinished. Nothing pulls them back. A single sentence at the end of a conversation can create 24 hours of mental pull.

---

## What NOT to Do

Do not add:
- **Push notifications about inactivity.** "You haven't opened the app in 3 days" is guilt, not value. The notification service correctly avoids this already. Keep it that way.
- **A "welcome back" flow or re-onboarding.** The returning user should see their Home exactly as it was — their reflection, their practices, their streaks (preserved by grace). No modal, no "we missed you" screen.
- **Gamification elements** (badges for week 2, milestone pop-ups, achievement screens). The identity reflection covers this territory with dignity. Badges cheapen it.
- **Weekly summary emails or reports.** These are content-consumption features, not practice features. The app's value lives inside the app.

---

## Implementation Order

1. **Grace days** — stop the bleeding. Users who broke streaks in week 2 are gone forever without this.
2. **Narrative threading in reflections** — create tomorrow-pull. This is the single biggest gap between what the skill document describes and what the app actually does.
3. **Surface insights on Home** — activate the "app knows me" loop before the user gives up.
4. **14-day identity reflection** — catch users at the exact moment they are deciding whether to stay.
5. **Forward threads in chat** — low effort, meaningful pull.

All five of these deepen existing features. None add a new tab, a new screen, or a new navigation element. None break the flow circle. They make the app feel alive where it currently feels static — and week 2 is exactly when "static" becomes "forgettable."
