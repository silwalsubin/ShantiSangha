# Phase 2 — AI Opponent

**Goal:** play complete games against the app at selectable difficulty, fully local.

## Tasks
1. **`ChessOpponent` protocol** — e.g. `func move(for position: ChessPosition) async -> ChessMove`.
2. **`Models/Chess/AIOpponent.swift`** — implement `ChessOpponent` via GameplayKit:
   - adapt the rules model to `GKGameModel` / `GKGameModelUpdate` / `GKGameModelPlayer`
   - use `GKMinmaxStrategist` (`maxLookAheadDepth` set from difficulty) to pick a move
   - run the search on a **background queue**; return on the main actor
   - a simple material + position evaluation for `GKGameModel.score(for:)`
3. **`ViewModels/ChessGameViewModel.swift`** (`@StateObject`):
   - holds position + status + difficulty
   - user move → validate/apply → if game continues, ask `ChessOpponent` for reply → apply
   - detect game-over (checkmate / stalemate / draw) and expose it
   - `newGame(difficulty:)`
4. **`Views/Chess/ChessHomeView.swift`** — "Play the app" + difficulty picker (Easy/Medium/Hard →
   depth), pushes `ChessGameView`. Serif, saffron/gold.
5. **Home entry** — add a serif "Chess" card to `Views/HomeView.swift` that pushes `ChessHomeView`
   via the existing `NavigationStack`.

## Acceptance checks
- [ ] Full games vs the app at Easy / Medium / Hard
- [ ] AI always plays legal moves
- [ ] Board stays responsive while the AI "thinks" (search off main thread)
- [ ] Reaching checkmate / stalemate ends the game correctly
- [ ] Difficulty visibly changes AI strength
