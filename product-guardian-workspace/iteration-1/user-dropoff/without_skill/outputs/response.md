# Week 2 Drop-off Analysis for ShantiSangha

## Why Week 2 is the Cliff

Week 1 is novelty: the daily reflection feels personal, the AI companion is surprising, setting goals feels like a fresh start. By week 2, the novelty wears off and the user faces the real question: **"Is this actually changing anything?"**

The app currently has no answer to that question. Here is what the user experiences by day 10:

- The daily reflection is nice but starts to feel repetitive (the prompt works hard to avoid repetition, but 10 reflections in, it still feels like the same format)
- Goals are checkboxes with streaks, but a 10-day streak doesn't feel meaningfully different from a 3-day streak
- The Journey tab shows stats but no narrative -- no sense of "where I was vs. where I am"
- There is no moment where the app says: "Look what you've built"

The core issue: **the app delivers daily value but not cumulative value.** Users who stay past week 2 need to feel that their practice is compounding, not just repeating.

## What to Do (in Priority Order)

### 1. Grace Days for Streaks (High Priority -- Build First)

This is the single highest-impact retention feature. Users who miss one day in week 2 see their streak reset to zero. That moment -- "I was at 12 and now I'm at 0" -- is when they leave and don't come back. Not because they failed, but because the app made them feel like they failed.

**Action:** Allow 1 grace day per 7-day window. A missed day doesn't break the streak. Visual distinction on the calendar (lighter shade). The AI acknowledges it warmly: "Rest is part of the practice."

This is already specced in `docs/product-goals/10-grace-days.md` but marked as "Lower" priority. Move it to the top. It is the single biggest reason people leave a streak-based app.

### 2. Celebration Moments at Day 7 (High Priority)

The user's first major milestone is day 7. Right now, hitting 7 consecutive days produces an inline text message. That is not enough. Day 7 should feel like a moment of genuine recognition.

**Action:** Build the celebration overlay from `docs/product-goals/07-celebration-moments.md`, but start with just the day-7 milestone. A simple expanded card with the streak number, a curated verse, and a warm message. One screen, one tap to dismiss. This gives users a reason to push through days 5-6 when motivation dips -- they know something meaningful is coming at day 7.

### 3. Weekly Insight on Journey Tab (High Priority)

By week 2, the user has journaled, chatted, and reflected for 7+ days. That is enough data for something powerful: a weekly synthesis. The Journey tab currently shows streaks and stats, which feel like spreadsheet data. What users need is **meaning**.

**Action:** Build the weekly insight card from `docs/product-goals/04-weekly-insight-on-journey.md`. One prominent card: "This week, your reflections centered on courage. You mentioned your father three times. You showed up for meditation 6 out of 7 days." This is the moment where scattered daily actions become a story. This is what makes week 2 feel different from week 1.

### 4. Evening Nudge (Medium Priority)

The evening nudge is already specced (`docs/product-goals/05-gentle-nudges-on-home.md`) and partially referenced in the Home doc. If users open the app in the evening and haven't checked in, the app is silent. Silence at 8 PM on day 10 is indistinguishable from the app not caring.

**Action:** Show a gentle, non-guilt message when goals are unchecked after 6 PM: "Your meditation practice is waiting for you -- no rush." This is not a push notification. This only appears when the user is already in the app. It is the difference between a tool and a companion.

### 5. Check-in Micro-Reflection (Medium Priority)

Check-ins are binary: done or skip. After two weeks of tapping "Done" on meditation, it starts to feel like checking a box on a to-do list. The ritual loses its meaning.

**Action:** Build the optional one-line note from `docs/product-goals/06-check-in-micro-reflection.md`. After tapping "Done," ask: "How did it go?" or "One word for today's practice." This takes 3 seconds, costs nothing, and transforms a checkbox into a micro-reflection. Over time, these notes feed into the AI companion's context and the weekly insight, creating a virtuous cycle.

## What NOT to Do

- **Do not add push notifications.** Users who are dropping off at week 2 are not dropping off because they forgot about the app. They are dropping off because the app stopped earning their attention. Push notifications for a spiritual practice app feel like nagging, not companionship.

- **Do not add more features or tabs.** The 3-tab structure (Home, Reflect, Journey) is correct. The problem is not missing features -- it is that existing features don't compound over time.

- **Do not add gamification.** No badges, no points, no leaderboards. The celebration moments are recognition, not rewards. There is a meaningful difference.

- **Do not add social features.** This is a private, sacred space. The moment you add sharing or community, you change the fundamental relationship the user has with the app.

## The Core Insight

Week 2 drop-off is a **meaning gap**, not a feature gap. The user has been practicing for 10 days and the app hasn't told them what that means. The daily reflection is a mirror for today. What is missing is a mirror for the journey so far.

Grace days prevent the catastrophic loss moment. Celebration moments reward consistency. The weekly insight turns data into narrative. Together, these three features answer the question every user asks in week 2: "Is this actually doing anything?" -- and the answer becomes: "Yes. Look."

## Recommended Build Order

1. Grace days (prevents the worst-case exit)
2. Day-7 celebration moment (rewards the first milestone)
3. Weekly insight on Journey (delivers cumulative meaning)
4. Evening nudge (strengthens the daily return)
5. Check-in micro-reflection (deepens the ritual)

Items 1-3 should be built before anything else. They directly address the week-2 cliff.
