# What's Next — Product Guardian Assessment

I audited every screen, every flow, every backend service. Here are the gaps that matter most, ranked by impact on the daily practice circle and retention hooks.

---

## 1. Home Tab Check-In Is Buried (HIGH IMPACT, LOW EFFORT)

**The problem:** The user opens the app, sees their reflection and progress rings — but to actually check in on a practice, they have to tap the Practices ring, navigate to RecurringSummaryView, then swipe on each task. That is 3 taps to do the single most important action in the app. The check-in — the thing that feeds the streak, the thing that closes the ring — is hidden behind a summary screen.

**What the user feels:** "I see my progress but I can't act on it without navigating away from Home." The Home tab shows the score but doesn't let you play the game.

**The fix:** Make practices tappable directly on Home. When the user taps the Practices ring (or add a practice list below it), each practice should be checkable with a single swipe or tap — right there on the Home screen. The RecurringSummaryView can still exist for the full view with undo/skip/delete, but the primary check-in action belongs on Home.

**Which hooks this strengthens:** Completion drive (the ring closes as you check in, right in front of you), streak protection (fewer taps = fewer abandoned check-ins).

**Files that change:** `HomeView.swift`, `HomeViewModel.swift`. Add an inline practice list below the progress rings with swipe-to-complete gesture. The TaskRow component already exists.

**What you would remove:** Nothing. The RecurringSummaryView stays as a detail view. Home just gains the primary action it's currently missing.

---

## 2. The Reflection Card Is a Dead End (HIGH IMPACT, LOW EFFORT)

**The problem:** The daily reflection — the primary reason to open the app — sits on the Home tab as static text. The user reads it and then... nothing. There is no forward action. No "this resonated" gesture. No path from the reflection into a conversation or journal entry about what it surfaced.

**What the user feels:** "That was nice." Then they scroll past it. The reflection is furniture when it should be a doorway.

**The fix:** Add a subtle interaction to the ReflectionCardView. Two options, both light:

- **Option A (minimal):** A long-press or tap reveals two actions: "Write about this" (opens journal with the reflection as context) and "Talk about this" (opens chat with the reflection pre-loaded as context). The AI companion already receives today's reflection in its system prompt — this just makes the connection explicit in the UI.
- **Option B (even lighter):** Tapping the reflection card navigates to a new chat with the reflection already acknowledged. The chat system prompt already handles this — the user just needs a path to get there.

**Which hooks this strengthens:** The Mirror (the reflection becomes interactive, not passive), Unfinished Thread (the user now has a reason to go deeper), Zeigarnik (they tapped "write about this" but haven't finished — that pulls them back).

**Files that change:** `ReflectionCardView.swift` (add tap/long-press gesture), `HomeView.swift` (handle navigation to chat or journal).

**What you would remove:** Nothing. This is strictly additive — one gesture on an existing component.

---

## 3. The 4th Tab Must Go (MEDIUM IMPACT, LOW EFFORT)

**The problem:** The app has 4 tabs: Home, Reflect, Journey, Settings. The product principles state 3 tabs as a sacred constraint. Settings is a 4th tab that breaks this rule. It contains account info, reminder preferences, debug tools (Hangfire, Logs), and server status. This is not a daily-use screen. It does not serve discipline, progress, or peace. It occupies prime navigation real estate.

**What the user feels:** Four choices at the bottom instead of three. The Settings tab creates decision weight every time they glance at the tab bar, and it will never be tapped as part of the daily practice circle.

**The fix:** Move Settings behind a gear icon in the Home tab's navigation bar (top-right). This is the standard iOS pattern — settings as a toolbar button, not a tab. The 3-tab constraint is restored: Home, Reflect, Journey.

**Files that change:** `MainTabView.swift` (remove 4th tab), `HomeView.swift` (add toolbar button for settings navigation).

**What you would remove:** The Settings tab item. The SettingsView itself stays — it just moves to a NavigationLink from Home's toolbar.

---

## 4. Journey Tab Lacks the Cliffhanger (MEDIUM IMPACT, MEDIUM EFFORT)

**The problem:** The Journey reflection is a one-shot summary of the selected period. It doesn't plant seeds, hint at emerging patterns, or create reasons to come back. The skill document describes a Cliffhanger Engine — unfinished observations, slow reveals, callbacks to past entries — but none of that is implemented. The Journey reflection reads like a report card, not a chapter ending.

**What the user feels:** "Okay, I see my stats." There is no narrative tension, no "I wonder what the app will say tomorrow." The Journey tab is informative but not magnetic.

**The fix:** Enhance the backend Journey reflection prompt to implement cliffhanger mechanics. Specifically:

- Feed the prompt the user's last 3 Journey reflections (to build continuity, not repeat).
- Add instructions for 1-in-4 reflections to plant an unfinished observation: "There's a pattern forming in your evening practices. It's not fully clear yet."
- Add instructions for monthly-period reflections to deliver a "season arc" — naming the chapter the user just lived through.
- Add a "callback" instruction: when viewing "Last month" or longer, reference a specific past journal entry or streak milestone and reframe its significance.

The frontend doesn't need to change — the reflection text already renders. The magic is in the prompt.

**Which hooks this strengthens:** The Surprise, the Cliffhanger Engine, the Season Arc. The user checks Journey not just to see stats but to hear what the narrator says next.

**Files that change:** `GoalsController.cs` (the journey/reflection endpoint), and the prompt within it. No iOS changes needed.

---

## 5. Insights Have No Lifecycle (MEDIUM IMPACT, MEDIUM EFFORT)

**The problem:** Insights are extracted from conversations and journals, stored forever, and displayed as a flat list on the Journey tab. There is no slow reveal (the skill's "Day 1: noticing something... Day 2: the pattern is clearer... Day 3: the full insight"). Insights appear fully formed, which makes them feel like notifications rather than discoveries. There is also no aging or archival — old insights dilute new ones.

**What the user feels:** The insights section on Journey is a growing pile. Some are months old and no longer relevant. There's no sense of "the app just figured something out about me."

**The fix (two parts):**

**Part A — Insight freshness:** Add a `createdAt`-based sort and a visual distinction for insights from the last 7 days (slightly brighter card, or a "New" indicator that fades after the user has seen it). Insights older than 90 days should auto-archive (soft delete) unless the user has explicitly saved them.

**Part B — Slow reveal (stretch):** When an insight is extracted, don't surface the full text immediately. Instead, on Day 1, show a teaser on the Home reflection: "A pattern is emerging from your recent journals..." On Day 2, the insight appears on Journey as a new card. This requires a small state machine on the backend (`InsightState: Emerging | Revealed | Archived`) and a tweak to the daily reflection prompt to mention emerging insights.

**Which hooks this strengthens:** Variable reward (insights appear unpredictably), the Slow Reveal (the user anticipates), the Surprise.

**Files that change:** Part A: `JourneyView.swift` (sort/fresh badge), backend `InsightsController` (archival). Part B: `SavedInsight` model (add state), `GenerateDailyReflectionJob.cs` (mention emerging insights), `JourneyView.swift` (new insight animation).

---

## Summary Table

| # | Proposal | Impact | Effort | Hook Strengthened |
|---|----------|--------|--------|-------------------|
| 1 | Check-in on Home | High | Low | Completion drive, streak |
| 2 | Reflection as doorway | High | Low | Mirror, unfinished thread |
| 3 | Remove 4th tab | Medium | Low | Simplicity (core principle) |
| 4 | Journey cliffhangers | Medium | Medium | Surprise, cliffhanger engine |
| 5 | Insight lifecycle | Medium | Medium | Variable reward, slow reveal |

**My recommendation:** Do 1, 2, and 3 together. They are all low-effort, they all strengthen the daily circle, and together they transform the Home tab from a dashboard you read into a place you act. The Home tab should be the place where you check in, feel seen by the reflection, and then choose to go deeper (chat, journal) or close the app feeling complete. Right now it's missing the "act" part (check-in is buried) and the "go deeper" part (reflection is a dead end). Fix both and the circle tightens.

Items 4 and 5 are the next tier — they make the app feel alive across days and weeks, not just within a single session. Do them after 1-3 ship.
