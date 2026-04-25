# Privacy

This is the user's private sacred space. No judgment. No sharing. No exceptions.

## Why this matters

People share their deepest fears, struggles, and vulnerabilities here — things they may not tell anyone else. If there is even a hint that this data could be seen by others, they will never open up. Privacy is not a feature. It is the foundation.

## Rules

- **Solo content is never shared with another user.** Journal entries, AI chat history, voice notes, daily reflections, goal titles, and "deeper why" text are NEVER visible to anyone else. This is the user's private record of self, and it stays private no matter who their friends are.
- **No analytics on content** — we may track usage events (taps, sessions) but NEVER analyze the content of conversations, journals, voice notes, or friend messages for business purposes
- **AI conversations are private** — the AI processes content to respond, but nothing is stored beyond what the user sees in their own account
- **No public profiles** — there is no concept of a public identity in this app. A friend sees only your chosen Display Name. There is no public profile page, no discoverable directory, no follower counts, no follower graph.
- **Data deletion must be real** — when a user deletes something, it is gone. Ending a friendship immediately revokes read access on both sides; the message thread is hard-deleted; nothing lingers.
- **Data export is a right** — users can download everything they've created at any time, including friend messages they sent or received.

## The Friends exception

A user may consciously connect with other users as Friends. Once connected, friends can send each other text, images, and voice messages. This is the ONLY social surface the app permits, and the boundary between "solo content" and "friend content" is sharp:

- **What a friend sees about you:** your chosen Display Name, and the messages you have explicitly sent to them. Nothing else.
- **What a friend NEVER sees:** journal entries, AI chat history, voice notes (the solo kind), daily reflections, goal titles, goal counts, streaks, "deeper why" text, insights, calendar history, or anything else you wrote for yourself rather than for them.
- **Friend messages are deliberately authored content.** Sending a text, image, or voice message to a friend is an explicit, per-message act of disclosure. This is categorically different from your solo records, which are never shared.
- **Friendships are private to the pair.** Friend A cannot see who else is in your friend list. There is no friend graph, no friends-of-friends, no public list. Each friendship row is independent.
- **Symmetric and ephemeral.** Either side can end a friendship at any time. When they do, the message thread is hard-deleted on both sides, the read grant is revoked, and stored media (images, voice files) is removed from object storage. No notification — the connection simply disappears.
- **Display Name is required to invite.** The user consciously chooses how they appear to friends before any invite link is generated.
- **Friend messages bypass the AI.** Messages between friends are NEVER sent to OpenAI, Anthropic, or any model provider. They are not embedded, summarized, indexed, or used for any AI feature. They are end-user-only.

## How this shows up in the product

- The app never asks users to share their reflections
- No "share to social" buttons anywhere
- The privacy page is written in warm, human language — not legalese
- Empty states say "this is your private space" to reinforce safety
- Error messages never expose other users' data
- Account deletion is self-serve and immediate

## How this shows up in code

- All queries are scoped to `UserId` — a user can never access another user's data
- JWT `sub` claim is the sole identity anchor
- No admin endpoints that expose user content
- Voice files are stored in private S3 buckets with no public access
- Database connections use SSL
- Secrets are managed via AWS Secrets Manager, never in code

## The promise

"Your thoughts, feelings, and reflections are yours alone. We will never read them, sell them, or share them with anyone. This is your space."

This promise must be visible in the app and honored in every line of code.
