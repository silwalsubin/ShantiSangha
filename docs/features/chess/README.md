# Chess

## Purpose
A quiet, single-player chess game played against the app. A calm, focused way to spend a few
minutes inside ShantiSangha — concentration as a form of stillness, not a competitive arcade.

## Scope
- **Now (V1): solo vs the app.** Fully local on iOS — no backend, no network. You play White
  against a computer opponent with selectable difficulty.
- **Later (deferred): friend mode.** Turn-based games with a friend over the existing realtime +
  push infrastructure. Designed but not built — see [friend-mode-later.md](friend-mode-later.md).

## Value
- A self-contained, offline, distraction-free game that fits the sacred aesthetic
- Reuses the existing SwiftUI + SpriteKit-in-SwiftUI pattern already in the app
- Architected so multiplayer can be added later without reworking the board or rules

## How it works (V1)
- **SceneKit** renders a 3D board (`ChessSceneController`) — perspective camera, real lighting +
  cast shadows, code-generated 3D pieces (`ChessPieces3D`), embedded in SwiftUI via `ChessSceneView`.
- A **hand-rolled Swift rules model** (`ChessPosition`) provides move legality, check/mate/stalemate,
  FEN (verified via perft).
- **GameplayKit** (`GKMinmaxStrategist`) chooses the computer's move on a background queue;
  difficulty maps to look-ahead depth, with a deliberate "thinking" pause.
- A `ChessBoardRenderer` protocol abstracts the board view, and a `ChessOpponent` protocol abstracts
  the opponent — so a networked `RemoteOpponent` can be added later without touching the rules.
- Chess is **landscape-only**, opened via `ChessPresenter` in a forced-landscape controller.

## Key files (iOS)
- `ios/ShantiSangha/Models/Chess/` — rules model + `ChessOpponent`/`ChessMode` + `AIOpponent.swift`
- `ios/ShantiSangha/Views/Chess/ChessBoardRenderer.swift` — renderer protocol (2D/3D agnostic)
- `ios/ShantiSangha/Views/Chess/ChessSceneController.swift` — 3D SceneKit scene, camera, input
- `ios/ShantiSangha/Views/Chess/ChessPieces3D.swift` — code-generated 3D piece geometry
- `ios/ShantiSangha/Views/Chess/ChessPresenter.swift` — landscape full-screen presentation
- `ios/ShantiSangha/Views/Chess/ChessGameView.swift` — game screen; custom floating header + mode menu
- `ios/ShantiSangha/ViewModels/ChessGameViewModel.swift` — game state + swappable opponent bridge
- Entry point: a "Chess" card on `ios/ShantiSangha/Views/HomeView.swift` → presents chess directly

## Design constraints
- No 5th tab (4-tab rule). Serif fonts (New York), saffron/gold, no emoji pieces. Landscape-only.

## Docs index
- [PROGRESS.md](PROGRESS.md) — master progress tracker
- [architecture.md](architecture.md) — design decisions
- [phase-1-board.md](phase-1-board.md) — board + rules tasks
- [phase-2-ai.md](phase-2-ai.md) — AI opponent tasks
- [phase-3-polish.md](phase-3-polish.md) — polish tasks
- [friend-mode-later.md](friend-mode-later.md) — deferred multiplayer design
