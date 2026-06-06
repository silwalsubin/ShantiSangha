# Chess — Architecture & Decisions

## Overview
V1 is entirely client-side on iOS. The board scene and rules model are **opponent-agnostic**;
the only thing that varies between "vs the app" and (future) "vs a friend" is where the reply move
comes from.

```
ChessHomeView ──pick difficulty──► ChessGameView (SpriteView + ChessBoardScene)
                                        ↕ ChessGameViewModel (@StateObject)
   user move → rules.validate+apply → animate
            → ChessOpponent.move(for:) → reply move → animate
```

`ChessGameViewModel` owns the authoritative game state (position/FEN, side-to-move, status),
drives the `ChessBoardScene` (which only renders), and asks a `ChessOpponent` for the reply.

## The `ChessOpponent` seam
A small protocol abstracts the opponent:
- `AIOpponent` (V1) — local GameplayKit `GKMinmaxStrategist`, no network.
- `RemoteOpponent` (later) — submits the move to the backend and surfaces the friend's move via
  realtime. Adding it does not touch the board or rules.

This seam is the one bit of "extra" structure we build now so multiplayer is additive later.

## Decisions
- **Solo first.** No backend/network → fastest path to a complete, testable feature, and the
  hardest work (board rendering + rules + input) is shared with friend mode anyway.
- **Rules engine = hand-rolled pure Swift** (decided 2026-06-06, deviating from the original
  SPM-package plan). Rationale: the build environment can't add/verify an SPM package, so a
  self-contained model keeps every file internally consistent and dependency-free. The intricate
  legality cases (en passant, castling through/into check, fifty-move, insufficient material) must
  be verified on first device build. The engine is isolated in `Models/Chess/` so it could be
  swapped for a package later without touching the scene/VM.
- **AI = GameplayKit `GKMinmaxStrategist`.** Zero external dependency, alpha-beta built in,
  difficulty via `maxLookAheadDepth`. Runs off the main thread. **Upgrade path:** bundle Stockfish
  (SPM, UCI) if the app needs to play strongly — swap behind `AIOpponent`.
- **SpriteKit via `SpriteView`.** Mirrors the existing
  `ios/ShantiSangha/Views/Friends/CircleSpriteSystemView.swift` pattern. The scene is a pure
  renderer with a single authoritative entry (`apply(position:)`); the VM is the source of truth.
- **No 5th tab.** Entry is a serif "Chess" card on `HomeView`; chess lives inside the existing
  navigation, honoring the 4-tab + sacred-aesthetic rules.

## Risks
- **AI perf:** minimax depth >3–4 in Swift can be slow → cap depth, run on a background queue.
- **Product fit:** competitive game on a calm app → keep it understated (serif, saffron, no emoji);
  consider running `product-guardian` / `sacred-ui`.
