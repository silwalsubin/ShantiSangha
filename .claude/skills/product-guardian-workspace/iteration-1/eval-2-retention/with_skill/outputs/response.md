# What Should We Build Next to Improve Retention?

## Audit of Current Features Against the Four Hooks

Before proposing anything new, I audited every existing feature against the four retention hooks (The Mirror, The Streak, The Unfinished Thread, The Surprise) and the Invisible Psychology principles. Here is where the app stands and where it quietly fails.

### What Is Working

**The Mirror (Daily Reflection)** is the strongest hook. The `GenerateDailyReflectionJob` gathers goals, streaks, conversation summaries, journal summaries, insights, and previous reflections to produce something genuinely personal. It avoids repetition. It never shames. The morning push delivers it to the lock screen. This is the primary reason to open the app, and it is well-executed.

**The Streak** is visible in two places: the heartbeat pulse line on `TaskRow` (7-day heat visualization) and the streak counters in `GoalDetailView` and `GoalCalendarView`. The swipe-to-check-in acknowledges milestones inline ("Day 14 -- two weeks strong"). This is solid.

**The Unfinished Thread** is partially present. One-time goals with due dates create forward pull. Overdue milestones get a subtle breathing glow. The evening nudge card appears after 6 PM if practices are undone.

### Where It Quietly Fails

**1. The Surprise hook is almost nonexistent.** Insights are extracted from conversations and journals, but they only appear on the Journey tab in a static list. There is no moment of unexpected discovery. The user never opens the app and finds something they did not expect. Insights sit passively -- they do not surface at the right time, in the right context. The "slot machine of spiritual apps" described in the Invisible Psychology section is missing.

**2. The Investment Loop is invisible -- literally invisible.** The reflection gets better over time because it draws from richer data, but the user has no way to feel this. A day-1 user and a day-90 user see the same card layout, the same interaction pattern. There is no moment where the app says (through its behavior, not through text) "I know you better now."

**3. Journey tab is a dead end for daily return.** Journey shows historical data -- completion rates, practice breakdowns, fulfilled commitments. But it refreshes only when the period changes or practices change. There is nothing on Journey that is genuinely new each day. Users who check Journey once learn what it shows and stop checking. The AI reflection on Journey (the period-based one) requires the user to actively navigate there and select a period. It does not pull them.

**4. Home has exactly two daily-refresh elements, and the skill requires three.** The daily reflection refreshes. Practice status refreshes. But there is no third element. The contextual journal prompt (`/journal/prompt`) is a daily-refresh element, but it is buried -- it only appears after the user taps the FAB, chooses journal, and starts a new entry. It never surfaces on Home.

**5. Completion drive is underused.** The progress circles on Home show "3 of 5" but there is no animation or acknowledgment when the ring closes. The `allPracticesDone` state shows a static text ("All practices complete. You showed up today.") with no animation, no warmth, no celebration that matches the effort. The moment of closing the ring -- the most psychologically satisfying moment in the daily loop -- is flat.

**6. Endowed progress (milestone proximity) is not implemented.** When a user is on day 28 of a streak, the reflection prompt includes the streak count for AI context, but nothing in the UI quietly acknowledges proximity to milestones like 30, 60, or 100. The `checkinMessage` in `TaskRow` only fires AFTER the milestone is hit, not as the user approaches it.

---

## Ranked Proposals: What to Build Next

### 1. Surface a Daily Insight on Home (High Impact, Low Effort)

**The problem:** Insights are extracted but buried. The Surprise hook is dead.

**The fix:** Add a single insight card below the reflection on `HomeView` -- one insight per day, selected from the user's saved insights they have not seen recently, or a newly extracted one. Not random -- chosen for relevance (recent, or thematically connected to today's reflection or active goals). If no insights exist yet, show nothing.

**Which hook this strengthens:** The Surprise. The user opens the app and sees something they said weeks ago, reframed as a pattern. "I tend to feel most grounded after morning walks." They did not ask for this. It was waiting for them.

**What changes:**
- Backend: New endpoint `GET /api/insights/daily` that selects one unseen or contextually relevant insight for today
- iOS: A new card in `HomeView` below the reflection, styled like the insight cards on Journey but with a subtle "From your reflections" label
- This also satisfies the "3 daily-refresh elements" requirement

**What it costs:** Minimal complexity. One card. One endpoint. No new navigation, no new tab, no new concept.

**The Retention Test:** Would the user miss this if they skipped a day? Yes -- tomorrow's surfaced insight will be different. Does it deepen over time? Yes -- more journals and conversations mean richer, more surprising insights to surface.

---

### 2. Animate the Ring Closure and Celebrate Completion (High Impact, Low Effort)

**The problem:** The most psychologically powerful moment in the daily loop -- completing all practices -- lands with a thud. A static line of text. No animation. No warmth.

**The fix:** When `allPracticesDone` becomes true:
- The progress ring fills with a satisfying spring animation and a brief gold shimmer
- The text transforms from "3 of 5" to a completion state with a gentle scale-up animation
- The completion message references the streak: "All practices complete. Day 12." (not "Day 12!" -- no exclamation, just the quiet weight of the number)
- A subtle haptic pulse marks the moment

**Which hook this strengthens:** The Streak (making it feel real) and Completion Drive (closing the ring must feel satisfying, not just look different).

**What changes:**
- `HomeView.swift`: Add animation states for ring completion
- `TaskRow.swift`: The heartbeat line could briefly pulse when the last practice completes
- The completion message should incorporate the lowest current streak count (to reinforce the one they are building)

**What it costs:** Zero new features. Zero new screens. Pure deepening of what exists.

**The Retention Test:** Does this give the user a reason to return? Indirectly but powerfully. The memory of closing the ring creates anticipation for doing it again tomorrow. The satisfaction compounds.

---

### 3. Milestone Proximity Awareness (Medium Impact, Low Effort)

**The problem:** Endowed progress is described in the Invisible Psychology section but not implemented. A user on day 28 of a streak has no quiet signal that day 30 is close. Their own mind could do the work, but the app does not give them the number.

**The fix:** When a user's streak on any practice is within 2 days of a milestone (7, 14, 30, 60, 100, 365), the `TaskRow` heartbeat visualization or the streak count should subtly surface the number. Not "2 more days!" -- just the number. "Day 28." The daily reflection prompt already has milestone detection; extend it to include proximity milestones in the context so the reflection can organically mention it.

**What changes:**
- `TaskRow.swift`: When `currentStreak` is within 2 of a milestone threshold, show "Day N" text next to the heartbeat instead of just the pulse line
- `GenerateDailyReflectionJob.cs`: Add milestone proximity to context (not just milestones hit today): "Their meditation streak is at 28 days (approaching 30)"
- This lets the reflection naturally say something like "Twenty-eight days of meditation. Almost a different kind of number."

**What it costs:** A few lines in `TaskRow` and one context line in the reflection job. No new UI concepts.

**The Retention Test:** Would the user miss this if they skipped a day? Absolutely. Skipping day 29 when you know day 30 is tomorrow has real psychological cost. That is loss aversion working honestly -- they earned the progress, and the app is simply showing them where they stand.

---

### 4. Journey "What Changed This Week" Auto-Reflection (Medium Impact, Medium Effort)

**The problem:** Journey tab has no daily-refresh content. It is a report card, not a living page. Users visit once, see their numbers, and leave. There is no Surprise, no Mirror, and no reason to return to Journey specifically.

**The fix:** At the top of the Journey tab (above the hero ring), show a single AI-generated sentence that compares this period to the previous period. Not a report -- an observation. "You journaled three times this week. Last week, none. Something shifted." This refreshes whenever the underlying data changes, and since practice data changes daily, it is effectively a daily-refresh element.

**What changes:**
- Backend: The existing `GET /api/goals/journey/reflection` endpoint already generates a period reflection. Enhance the prompt to include comparison with the prior equivalent period (last week vs. the week before, last month vs. the month before). The data is already loaded in `JourneyView.loadReflectionData`.
- iOS: The reflection already renders in `JourneyView`. The change is to the prompt, not the UI.

**What it costs:** One prompt enhancement. No new endpoints, no new views. The comparison data needs to be fetched server-side (one additional query for the prior period's summary).

**The Retention Test:** Does this create something new each day? Yes -- because practice data changes daily, the comparison changes. Does it deepen over time? Yes -- the comparisons become more meaningful with more history.

---

### 5. Contextual Journal Prompt on Home (Low-Medium Impact, Low Effort)

**The problem:** The journal prompt (`/journal/prompt`) generates a personalized, AI-driven writing prompt based on the user's data and date. But it only appears after three taps (FAB -> journal icon -> new entry screen). The user never sees it unless they already decided to journal. It cannot pull them toward journaling.

**The fix:** On Home, below the reflection card (and below the surfaced insight from Proposal 1, if built), show the journal prompt as a tappable card: "What moment stood out today..." (or whatever the AI generated). Tapping it opens a new journal entry with that prompt pre-loaded. This turns the prompt from a hidden feature into a gentle invitation.

**What changes:**
- `HomeView.swift`: Fetch the journal prompt alongside the reflection (the endpoint already exists). Show it as a subtle, low-profile card. Tapping navigates to `JournalEditorView` with `isNew: true`.
- The card should only appear if the user has not journaled today (to avoid redundancy).

**What it costs:** One card on Home. One additional API call on load (but the endpoint is fast -- it is a simple prompt, not a generation job). The Home screen gets slightly longer, but this card is contextual (disappears after journaling) so it does not add permanent complexity.

**The Retention Test:** This strengthens The Unfinished Thread. The user sees a question addressed to them. It lingers. Even if they do not tap it now, the question sits in their mind. "What moment stood out today..." And when they come back in the evening, the nudge card is there, and the journal prompt is still waiting. Two gentle pulls instead of one.

---

## What I Would NOT Build

- **Weekly email summaries or digests.** These move value outside the app. The goal is daily return to the app, not passive consumption in email.
- **Streak freeze or grace days UI.** The skill says to offer grace but never make streaks feel cheap. The current "skip" mechanic is sufficient. Adding visible streak protection creates anxiety about the mechanic itself.
- **Push notifications for missed days.** The skill is explicit: "You haven't opened the app" notifications are never acceptable. The morning reflection push is the only proactive notification that earns its interruption cost.
- **Social proof features.** "1,247 people meditated today" violates the sacred private space. The reflection prompt already includes universal human experience language when appropriate.
- **Achievement badges or milestone celebration screens.** The acknowledgment should be woven into existing interactions (the check-in message, the reflection), not surfaced as a separate gamification layer.

## Priority Order

1. **Surface a Daily Insight on Home** -- highest impact, directly addresses the missing Surprise hook, satisfies the 3-daily-refresh requirement
2. **Animate Ring Closure** -- transforms the most important daily moment from flat to memorable, pure deepening
3. **Milestone Proximity** -- activates the endowed progress mechanic that is described but unbuilt, a few lines of code with outsized psychological effect
4. **Journey Comparison Reflection** -- rescues Journey from being a static report card, medium effort
5. **Journal Prompt on Home** -- strengthens the Unfinished Thread, but lower priority because it addresses journal engagement (a secondary loop) rather than the primary daily return loop
