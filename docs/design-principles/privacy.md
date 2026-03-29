# Privacy

This is the user's private sacred space. No judgment. No sharing. No exceptions.

## Why this matters

People share their deepest fears, struggles, and vulnerabilities here — things they may not tell anyone else. If there is even a hint that this data could be seen by others, they will never open up. Privacy is not a feature. It is the foundation.

## Rules

- **User data is never shared** with third parties, advertisers, or other users. Period.
- **No social features** that expose one user's content to another
- **No analytics on content** — we may track usage events (taps, sessions) but NEVER analyze the content of conversations, journals, or voice notes for business purposes
- **AI conversations are private** — the AI processes content to respond, but nothing is stored beyond what the user sees in their own account
- **No public profiles** — there is no concept of a public identity in this app
- **Data deletion must be real** — when a user deletes something, it is gone. No soft deletes that linger. No "we keep it for 30 days."
- **Data export is a right** — users can download everything they've created at any time

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
