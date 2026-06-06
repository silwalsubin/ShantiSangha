# Phase 1 — Board + Rules (local hot-seat, no AI)

**Goal:** a playable two-sides-on-one-device chess board with correct rules and smooth animation.
This is the hardest UI work; no AI and no network yet.

## Tasks
1. **Add chess rules dependency** — add a Swift chess rules SPM package (e.g. ChessKit) to the
   Xcode project. Confirm it builds for the iOS 26 target.
2. **`Models/Chess/` rules wrapper** — thin wrapper over the package exposing what the app needs:
   - current position from/to FEN
   - `legalMoves(from square)` for highlighting
   - `apply(move)` returning the new position + any capture/promotion/castle/en-passant info
   - status: in-check, checkmate, stalemate, draw
3. **`Views/Chess/ChessBoardScene.swift`** — `SKScene` with three layers: tiles (8×8, alternating
   saffron/parchment), pieces (`SKSpriteNode`), highlights (selected square + legal destinations).
   Single authoritative entry `apply(position:)` that diffs and animates to the new position.
4. **Input** — tap-to-select then tap-to-move, and drag-to-move; map scene coordinates ↔ squares;
   only allow legal destinations (from the rules wrapper).
5. **Animations** — `SKAction` for slide, capture (fade/remove), castling (two pieces), promotion.
6. **Board orientation + promotion** — flip support; promotion picker (Q/R/B/N) in the app's style.
7. **Minimal `ChessGameView`** — host the `SpriteView`, alternate turns locally (hot-seat).

## Acceptance checks (run in app — you run `xcodebuild`)
- [ ] Play a full legal game with both sides on one device
- [ ] Illegal moves are rejected (piece returns to origin)
- [ ] Castling, en passant, and promotion all render correctly
- [ ] Legal-destination highlights appear on select
- [ ] No layout breakage at 375px width; serif / saffron-gold / no emoji
