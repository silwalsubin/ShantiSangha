# ShantiSangha iOS

SwiftUI iOS app for ShantiSangha. Shares the same backend API as the web app.

## Setup

1. Open Xcode
2. File → New → Project → iOS → App
3. Product Name: `ShantiSangha`
4. Interface: SwiftUI
5. Language: Swift
6. Minimum Deployment: iOS 17.0
7. Save in this `ios/` directory
8. Delete the auto-generated ContentView.swift
9. Drag the existing `ShantiSangha/` folder into the Xcode project navigator
10. Build and run

## Architecture

```
ShantiSangha/
├── ShantiSanghaApp.swift    # Entry point — auth gate
├── Models/
│   ├── Task.swift           # Task, Goal, CheckIn types
│   └── DesignTokens.swift   # Sacred color palette
├── Services/
│   ├── ApiService.swift     # HTTP client (mirrors useApi)
│   ├── AuthService.swift    # Clerk web OAuth + keychain
│   └── FeedbackService.swift # Spiritual feedback generator
├── ViewModels/
│   └── HomeViewModel.swift  # Task data + actions (mirrors useGoals)
└── Views/
    ├── LoginView.swift      # Sign in screen
    ├── MainTabView.swift    # Tab navigation (Home, Reflect, Journey)
    ├── HomeView.swift       # "What needs your attention today?"
    └── Components/
        └── TaskRow.swift    # Task card with menu (mirrors TaskItem.vue)
```

## Mapping to Web App

| iOS | Web | Purpose |
|-----|-----|---------|
| `DesignTokens.swift` | `tailwind.config.js` | Design tokens |
| `ApiService.swift` | `useApi.ts` | HTTP client |
| `HomeViewModel.swift` | `useGoals.ts` | Task data + actions |
| `FeedbackService.swift` | `useGoals.ts` (generateFeedback) | Spiritual messages |
| `TaskRow.swift` | `TaskItem.vue` | Task card component |
| `HomeView.swift` | `home.vue` | Home page |
| `LoginView.swift` | `login.vue` | Auth screen |
| `MainTabView.swift` | `AppLayout.vue` | Navigation shell |

## Development Workflow

1. Build and test the feature in the web app first
2. Port the feature to Swift following the same architecture
3. Both clients share the same backend API
