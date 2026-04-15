# Daily Reflection

## Purpose
A single AI-generated observation about the user that appears at the top of Home when they open the app. It's the first meaningful thing they read each day — a mirror, not a task.

## Value
- Gives the user a reason to return to the app daily: curiosity about what it noticed
- Makes "the app knows you" tangible — draws from journals, conversations, goals, streaks, and past reflections
- Never shames what was missed — only observes what is
- Replaces generic motivation with personal observation

## How it works
- A Hangfire job (`GenerateDailyReflectionJob`) gathers context about the user: active goals with streaks, recent conversation summaries, recent journal summaries, saved insights, and the last few reflections (to avoid repeating themes)
- GPT generates a 2–3 sentence reflection (max 50 words) using a tightly scoped prompt that forbids advice, motivation, and mentions of inactive goals
- Generation is lazy: the first `GET /api/reflection/today?date=YYYY-MM-DD` call for a given user-date triggers the job and returns `{ content: null }`; the client polls up to 5 times (3s apart) for the result
- On completion, a silent push (`type: "reflection"`) is sent so HomeView can refresh
- Stored one row per user per local date in `DailyReflections`

## Key files
- Backend model: `backend/ShantiSangha.Wellness/Models/DailyReflection.cs`
- Backend job: `backend/ShantiSangha.Wellness/Jobs/GenerateDailyReflectionJob.cs`
- Backend controller: `backend/ShantiSangha.Wellness/Controllers/ReflectionController.cs`
- iOS card: `ios/ShantiSangha/Views/ReflectionCardView.swift`
- iOS Home loader: `ios/ShantiSangha/Views/HomeView.swift` (`loadReflection()`)
- iOS widget: `ios/ShantiSanghaWidget/ShantiSanghaWidget.swift`

## API endpoints
- `GET /api/reflection/today?date=YYYY-MM-DD` — fetch or lazily trigger today's reflection
- `POST /api/debug/hangfire/test-reflection` — debug trigger: deletes the cached reflection and enqueues a fresh generation

## Design rules for the prompt
- Maximum 50 words, two to three short sentences
- Must reference specific user data — never generic motivation
- Only speaks to what the user HAS done, never what they haven't
- No advice, no instructions, no exclamation marks
- Welcomes returning users without guilt
- Must not repeat themes from the user's previous reflections
