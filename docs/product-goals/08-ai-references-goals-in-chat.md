# 08 — AI References Goals in Conversation

## Priority: Lower
## Phase: 3 — The Companion Grows
## Tab: Reflect (Chat)
## Depends on: #02 (Context-Aware Companion)

## The Problem

Even after the AI has context (goal #02), it will only use that context when directly relevant. The next step is for the AI to *weave* goal awareness into natural conversation — bringing up goals when the moment is right, not just when asked.

## What to Build

Enhance the AI system prompt with behavioral instructions for proactive goal engagement:

- When the user talks about stress, the AI can gently ask about their calming practices
- When the user mentions feeling stuck, the AI can reference their "Deeper Why"
- When the user shares a win, the AI can connect it to their goal progress
- The AI should never feel like a reminder system — it should feel like a friend who remembers what matters to you

## Why This Matters

This is the leap from "AI that knows about you" to "AI that cares about you." It's the difference between a doctor reading your chart and a friend who remembers you mentioned your back was hurting last week.

## Scope

- Backend: refine the system prompt instructions for when and how to reference goals
- Requires #02 to be complete and stable first
- Iterative — tune based on real conversations, not spec

## What This Replaces

Nothing new. Deepens the behavior established in #02.

## Definition of Done

User talks about a difficult day and the AI naturally — without being asked — connects it to one of their goals or their deeper intention.
