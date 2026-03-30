# iOS Architecture

## Overview

SwiftUI app targeting iOS 17+. Shares the same backend API as the web app. Follows MVVM pattern with async/await concurrency.

## Directory Structure

```
ios/ShantiSangha/
├── ShantiSanghaApp.swift       # Entry point — auth gate
├── Models/                     # Data types and design tokens
├── Services/                   # API, auth, business logic
├── ViewModels/                 # Observable state for views
└── Views/                      # SwiftUI views
    └── Components/             # Reusable view components
```

## Layers

### Models

Data types that match the backend API responses. Mirrors `frontend/src/types/index.ts`.

- `Task.swift` — AppTask, Goal, CheckIn, TaskType
- `DesignTokens.swift` — Color extensions matching `sacred-*` Tailwind tokens

### Services

Stateless or singleton services for business logic and external communication.

| Service | Web Equivalent | Purpose |
|---------|---------------|---------|
| `ApiService` | `useApi.ts` | HTTP client with Clerk JWT auth |
| `AuthService` | Clerk Vue plugin | Web-based OAuth via ASWebAuthenticationSession |
| `FeedbackService` | `useGoals.ts` (generateFeedback) | Spiritual feedback messages |

**ApiService** is an `actor` (thread-safe singleton). All HTTP methods are async and throw on error.

**AuthService** is an `@MainActor ObservableObject`. Persists the session token in Keychain. Publishes `isAuthenticated` for the app to react to.

### ViewModels

`@MainActor ObservableObject` classes that manage state for each screen. Mirrors frontend composables.

| ViewModel | Web Equivalent | Purpose |
|-----------|---------------|---------|
| `HomeViewModel` | `useGoals.ts` | Load tasks, check-in, undo, delete, create |

**Pattern**: Each ViewModel owns its data (`@Published`), exposes computed filtered lists, and has async action methods.

### Views

SwiftUI views. Smart views (pages) own a ViewModel. Dumb views (components) receive data via parameters.

| View | Web Equivalent | Purpose |
|------|---------------|---------|
| `HomeView` | `home.vue` | "What needs your attention today?" |
| `TaskRow` | `TaskItem.vue` | Task card with menu and actions |
| `LoginView` | `login.vue` | Sign in screen |
| `MainTabView` | `AppLayout.vue` | Tab navigation |

## Design Tokens

All colors are defined as `Color` extensions in `DesignTokens.swift`:

```swift
Color.sacredGold      // #c4873b
Color.sacredGoldDark  // #8b5a1b
Color.sacredText      // #2b1e10
Color.sacredBg        // #faf5ed
Color.sacredGreen     // #7aa87a
Color.sacredRed       // #b45a3c
```

**Rule**: No hex literals in views. Use `Color.sacred*` tokens.

## Auth Flow

1. App launches → checks Keychain for stored session token
2. If token exists → set authenticated, configure ApiService token provider
3. If no token → show LoginView
4. User taps "Sign in" → ASWebAuthenticationSession opens Clerk sign-in page
5. User authenticates → Clerk redirects back with session token
6. Token stored in Keychain → app shows MainTabView

## API Communication

All API calls go through `ApiService`:

```swift
let tasks: [AppTask] = try await ApiService.shared.get("/goals/today?date=2026-03-30")
let _: CheckInResponse = try await ApiService.shared.post("/goals/\(id)/checkin", body: body)
try await ApiService.shared.delete("/goals/\(id)")
```

## Conventions

### Naming
- Views: `XxxView.swift` (e.g., `HomeView.swift`)
- ViewModels: `XxxViewModel.swift` (e.g., `HomeViewModel.swift`)
- Components: descriptive name (e.g., `TaskRow.swift`)
- Services: `XxxService.swift`

### Adding a new feature
1. Build and test in web app first
2. Add model types to `Models/` if needed
3. Create ViewModel in `ViewModels/`
4. Create View in `Views/`
5. Wire into navigation (MainTabView or NavigationStack)
6. Use `Color.sacred*` design tokens

### Concurrency
- ViewModels are `@MainActor` — all published state updates happen on main thread
- ApiService is an `actor` — thread-safe by default
- Use `Task { await vm.action() }` from view button handlers
