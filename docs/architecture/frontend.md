# Frontend Architecture

## Overview

Vue 3 + TypeScript + Tailwind CSS. Single-page app with Clerk authentication, lazy-loaded routes, and composable-first data management.

## Directory Structure

```
frontend/src/
├── types/
│   └── index.ts              # Shared TypeScript interfaces
├── composables/
│   ├── useApi.ts             # HTTP client with Clerk auth
│   ├── useGoals.ts           # Goal/task CRUD, check-ins, feedback
│   └── useLocalDate.ts       # Timezone-safe date helpers
├── components/
│   ├── TaskItem.vue          # Reusable task card with actions
│   └── icons/
│       └── SacredIcons.vue   # Custom SVG icon system
├── layouts/
│   └── AppLayout.vue         # Authenticated app shell (sidebar + mobile nav)
├── pages/
│   ├── login.vue             # Clerk sign-in
│   ├── signup.vue            # Clerk sign-up
│   └── app/
│       ├── home.vue          # "What needs your attention today?"
│       ├── journey.vue       # Progress tracking, streaks
│       ├── goal-detail.vue   # Single goal view with history
│       └── reflect/
│           ├── index.vue     # Timeline: conversations + journals + voice
│           ├── chat.vue      # Streaming AI conversation
│           ├── journal-new.vue   # New journal entry
│           ├── journal-edit.vue  # Edit journal entry
│           └── voice-detail.vue  # Voice note playback
├── router/
│   └── index.ts              # Route definitions and auth guard
├── assets/
│   └── tailwind.css          # Tailwind imports
├── App.vue                   # Root component (just RouterView)
└── main.ts                   # App entry point
```

## Layers

### Types (`src/types/`)

All shared interfaces live in `types/index.ts`. Page-specific types that are only used in one file can stay local. Anything referenced by multiple files must be here.

Key types: `Task`, `Goal`, `CheckIn`, `Message`, `Conversation`, `JournalEntry`, `VoiceEntry`, `TimelineItem`.

### Composables (`src/composables/`)

Composables encapsulate reusable logic. Each composable is a function that returns reactive state and methods.

| Composable | Purpose |
|---|---|
| `useApi()` | HTTP client. Wraps `fetch` with Clerk JWT auth, JSON handling, and error throwing. All API calls go through this. |
| `useGoals()` | Goal/task management. Loads recurring tasks and milestones, handles check-ins, undo, delete, progress updates. Generates spiritual feedback messages. Returns computed lists (active, completed, skipped). |
| `useLocalDate()` | Timezone utilities. Returns the user's local date as `YYYY-MM-DD` string for API calls, plus date formatting helpers. |

**Pattern**: Composables are stateful (they hold `ref`s) but not singletons. Each component that calls `useGoals()` gets its own instance. If shared state is needed across components, move to a provide/inject pattern or a singleton composable.

**When to create a new composable**: When logic is used by 2+ pages, or when a page's `<script>` exceeds ~100 lines of data management code.

### Components (`src/components/`)

Reusable UI components. Each component receives props and emits events — no direct API calls.

| Component | Purpose |
|---|---|
| `TaskItem.vue` | Task card. Shows title, type icon, check-in state, three-dot menu (mark complete, skip, update progress, delete), progress bar for milestones. Emits: `done`, `skip`, `undo`, `delete`, `navigate`, `progress`. |
| `SacredIcons.vue` | SVG icon library. Renders inline SVGs by name. Icons: `vajra`, `lotus`, `om`, `dharma`, `chakra`, `diya`, `shankha`, `check`, `skip`, `recurring`, `target`, `flame`, `dialogue`, `scroll`. |

**Pattern**: Components are dumb — they don't fetch data or manage state. They receive everything via props and communicate up via events. This makes them testable and reusable.

### Pages (`src/pages/`)

Pages are smart components that wire composables to UI. Each page corresponds to a route.

**Page responsibilities**:
1. Call composables to load data (`onMounted`)
2. Pass data to components via props
3. Handle component events by calling composable methods
4. Manage page-local UI state (form visibility, loading states)

**Pages should NOT**: Make direct `fetch` calls (use `useApi`), define shared types (use `types/`), or contain business logic (use composables).

### Layouts (`src/layouts/`)

`AppLayout.vue` wraps all authenticated pages. Provides:
- Desktop sidebar with nav (Home, Reflect, Journey)
- Mobile top bar + bottom tab navigation
- Page transition animation (fade)
- Clerk UserButton for profile/logout

### Router (`src/router/`)

Three route groups:
- `/login`, `/signup` — guest-only (redirect to `/app/home` if signed in)
- `/app/*` — authenticated (redirect to `/login` if not signed in)
- `/` — redirects to `/app/home`

All page components are lazy-loaded via dynamic imports. Auth guard waits for Clerk to load before checking auth state.

## Design System

### Colors (Tailwind tokens)

Defined in `tailwind.config.js` under `theme.extend.colors.sacred`:

| Token | Value | Usage |
|---|---|---|
| `sacred-gold` | `#c4873b` | Primary accent, buttons, active states |
| `sacred-gold-dark` | `#8b5a1b` | Gradient endpoints, hover states |
| `sacred-text` | `#2b1e10` | Primary text |
| `sacred-text-secondary` | `#6b5740` | Body text, descriptions |
| `sacred-muted` | `#9a8568` | Subtle text, timestamps |
| `sacred-label` | `#a38d6d` | Section labels, uppercase headings |
| `sacred-bg` | `#faf5ed` | Page background |
| `sacred-bg-warm` | `rgba(250,245,237,0.95)` | Input backgrounds, overlays |
| `sacred-bg-card` | `rgba(250,245,237,0.88)` | Card backgrounds |
| `sacred-bg-card-inner` | `rgba(250,245,237,0.7)` | Inner card / task rows |
| `sacred-bg-hover` | `rgba(139,90,43,0.06)` | Hover states |
| `sacred-gold-light` | `rgba(196,135,59,0.06)` | Active pill backgrounds |
| `sacred-green` | `#7aa87a` | Success, completed state |
| `sacred-green-bg` | `rgba(122,168,122,0.06)` | Completed task background |
| `sacred-green-border` | `rgba(122,168,122,0.25)` | Completed task border |
| `sacred-red` | `#b45a3c` | Overdue, danger |
| `sacred-red-bg` | `rgba(180,90,60,0.06)` | Overdue task background |
| `sacred-border` | `rgba(139,90,43,0.12)` | Card borders |
| `sacred-border-subtle` | `rgba(139,90,43,0.1)` | Task row borders |
| `sacred-border-strong` | `rgba(139,90,43,0.15)` | Emphasized borders |

**RULE: No raw hex colors or rgba values in .vue files.** Every color must use a `sacred-*` token from `tailwind.config.js`. If a new color is needed, add it to the config first.

### Shadows

| Token | Usage |
|---|---|
| `shadow-sacred` | Cards |
| `shadow-sacred-lg` | Elevated cards |
| `shadow-sacred-button` | CTA buttons |
| `shadow-sacred-dropdown` | Dropdown menus |

### Typography

All font size tokens defined in `tailwind.config.js`:

| Token | Size | Usage |
|---|---|---|
| `text-sacred-xs` | 9px, uppercase, bold, tracked | Section group labels |
| `text-sacred-label` | 10px, uppercase, semibold, tracked | Page-level labels ("Your Dharma") |
| `text-sacred-caption` | 10px, uppercase, medium, tracked | Timestamps, metadata |
| `text-sacred-body` | 14px, relaxed line height | Body text |
| `text-sacred-heading` | 24px, semibold | Page headings |
| `text-sacred-heading-sm` | 20px, semibold | Section headings |

Standard Tailwind `text-sm`, `text-xs`, `font-serif`, `font-semibold` are still used for one-off sizing. The `sacred-*` tokens are for recurring patterns.

**RULE: No arbitrary font sizes like `text-[9px]` or `text-[10px]` in .vue files.** Use the `text-sacred-*` tokens instead.

### Icons

Custom SVG icons via `SacredIcons.vue`. Usage: `<SacredIcons name="vajra" :size="22" />`. No external icon library.

## Authentication

Clerk handles all auth. Integration points:
- `main.ts` — registers Clerk plugin with publishable key
- `router/index.ts` — guard checks `useAuth().isSignedIn`
- `useApi.ts` — attaches JWT via `useAuth().getToken()`
- `login.vue` / `signup.vue` — render Clerk's `<SignIn>` / `<SignUp>`
- `AppLayout.vue` — renders Clerk's `<UserButton>`

No custom auth logic exists in the app.

## API Communication

All API calls go through `useApi()` composable. Pattern:

```typescript
const api = useApi()
const data = await api.get<MyType>('/endpoint')
await api.post('/endpoint', { body })
await api.patch('/endpoint', { partial })
await api.delete('/endpoint')
```

The composable automatically:
- Adds `Content-Type: application/json`
- Attaches Clerk JWT as `Authorization: Bearer <token>`
- Throws on non-2xx responses
- Returns `undefined` for 204 responses

Streaming (chat) uses raw `fetch` with `ReadableStream` for SSE parsing.

## Conventions

### File naming
- Pages: `kebab-case.vue` (e.g., `goal-detail.vue`, `journal-new.vue`)
- Components: `PascalCase.vue` (e.g., `TaskItem.vue`, `SacredIcons.vue`)
- Composables: `camelCase.ts` prefixed with `use` (e.g., `useGoals.ts`)
- Types: `index.ts` in `types/` directory

### Component pattern
```vue
<script setup lang="ts">
// 1. Imports
// 2. Props & emits
// 3. Composables
// 4. Reactive state
// 5. Computed properties
// 6. Methods
// 7. Lifecycle hooks
</script>

<template>
  <!-- Single root element -->
</template>
```

### Adding a new feature
1. Define types in `types/index.ts`
2. Create composable in `composables/` if logic is shared
3. Create component in `components/` if UI is reusable
4. Create page in `pages/app/`
5. Add route in `router/index.ts`
6. Use `sacred-*` design tokens for styling
