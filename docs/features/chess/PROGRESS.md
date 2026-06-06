# Chess — Progress Tracker

**Current status:** Moved to a **3D SceneKit board** (user request). Engine verified (perft +
terminal). The board now renders via `ChessSceneController` (SceneKit: perspective camera, key
light with real cast shadows, code-generated 3D pieces, tap-to-move, lift/glide animations,
promotion overlay). The VM talks to it through a `ChessBoardRenderer` protocol, so the engine/VM
are unchanged. AI now has a deliberate "thinking" pause. Mode chips (Gentle/Measured/Sharp/
2 Players) live on the game screen; Home opens straight into `ChessGameView`.

**Design choices (device-tuned):** board is full-bleed (no wooden frame, near edge toward the
phone's bottom corners); opponent pieces are **dark antique gold** (not black) so they read on the
dark board and match the saffron palette; mode/new-game/undo/reset-view live in a top-right `⋯`
menu so the board stays the focus.

**Landscape-only, no portrait flash:** chess opens via `ChessPresenter.present()` — a full-screen
**`LandscapeHostingController`** (overrides `supportedInterfaceOrientations = .landscape`) presented
modally, so iOS rotates it *during* presentation and it's landscape from the first frame. The Home
"Chess" card is a Button (not a NavigationLink). `AppDelegate.orientationLock` defaults to
`.portrait` (rest of app portrait-locked, mobile-first) and is opened to landscape only while chess
is presented. Close/back + "Leave" call `onClose` which dismisses and restores portrait.

**No nav bar — custom floating header:** the system nav bar is hidden (`.toolbar(.hidden,
for: .navigationBar)`, status bar hidden); a custom transparent `topBar` overlays the full-bleed
board with circular back (left) + centered status + ⋯ menu (right), so the board shows through
behind it. Board uses `.ignoresSafeArea()` (all edges); the top bar respects safe area.

**Near-edge-pinned tilt camera:** the camera pivots around the board's **near (bottom) edge**
(`pivotNode` at world z=4) and always looks at it with a fixed `cameraShift` so that edge is
**pinned on screen and never moves**. One-finger **vertical** drag changes only the elevation
(`camPitch`, clamped 0.30–0.95) — no yaw spin, no zoom. Device motion (`MotionManager` via Combine)
nudges only the elevation (roll ignored). "Reset view" snaps the tilt back. Tune `cameraDistance`,
`cameraShift`, `defaultPitch` for landscape framing.

**Still tuning by eye on device** (can't verify here): camera framing (height/distance/FOV/aim in
`buildCamera`), light/shadow intensity, and piece proportions. Knight is the **box-built** version
(extruded-silhouette attempt was reverted per user). Motion parallax dialed down to ~3°.

**Known ceiling:** code-generated pieces will stay stylized. A truly realistic set needs a real 3D
model asset (.usdz/.scn/.obj) imported into the project — offered, not yet chosen. The old 2D
SpriteKit board has been **deleted** (3D confirmed working on device).

3D files: `Views/Chess/ChessBoardRenderer.swift` (protocol), `ChessPieces3D.swift` (piece geometry),
`ChessSceneController.swift` (scene + holder + UIViewRepresentable).

**Decision (2026-06-06):** rules engine is hand-rolled pure Swift, not an SPM package — see
architecture.md. **Verified** by compiling the engine standalone: perft(4)=197281 and Kiwipete
perft(3)=97862 match reference; fool's-mate/stalemate/insufficient-material detection correct;
GKMinmaxStrategist returns legal moves in self-play.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done

---

## Phase 0 — Tracking docs
- [x] Create `docs/features/chess/` folder + doc set
- [x] Seed this tracker with all phases/tasks
- [x] Link Chess into the Features list in `CLAUDE.md`

## Phase 1 — Board + rules (local hot-seat, no AI)
- [x] ~~SPM dependency~~ → hand-rolled engine: `Models/Chess/ChessCore.swift` + `ChessPosition.swift`
- [x] Rules: legality, check/mate/stalemate, FEN, legal-destination lookup, insufficient material
- [x] `Views/Chess/ChessBoardScene.swift` — tiles + piece layer + highlight layer (Unicode figurines, no emoji)
- [x] Tap-to-select / tap-to-move input mapped to squares (drag deferred to Phase 3)
- [x] `SKAction` move / capture / castling-rook / promotion animations
- [x] Board flip (orientation) + on-board promotion picker overlay
- [x] `ChessGameView` wiring the scene (works for hot-seat and vs-computer)
- [x] **Verified (standalone):** perft(1..4) + Kiwipete perft(1..3) exact; mate/stalemate/draw correct
- [ ] **Device test:** full legal hot-seat game; castling / en passant / promotion render

## Phase 2 — AI opponent
- [x] `ChessOpponent` protocol + `ChessDifficulty` (Gentle/Measured/Sharp → depth 1/2/3)
- [x] `Models/Chess/AIOpponent.swift` — `GKGameModel`/`GKGameModelPlayer` + `GKMinmaxStrategist`
- [x] AI search runs on a background queue (`DispatchQueue.global`), async via continuation
- [x] `ViewModels/ChessGameViewModel.swift` — state + user→AI reply loop + game-over + undo
- [x] `Views/Chess/ChessHomeView.swift` — "Play the app" difficulty picker + "Side by side" hot-seat
- [x] "Chess" entry card on `Views/HomeView.swift` → `ChessHomeView`
- [x] Chess added to Features list in `CLAUDE.md`
- [x] **Verified (standalone):** GKMinmaxStrategist returns legal moves across self-play plies
- [ ] **Device test:** full games vs app at each difficulty; no UI freeze while thinking

## Phase 3 — Polish
- [ ] Check indicator + last-move highlight
- [ ] Game-over overlay with New Game
- [ ] Optional undo
- [ ] Optional persist-in-progress game (JSON-file pattern from `ChatCache.swift`)
- [ ] Haptics (CoreHaptics) on move/capture
- [ ] Reduce Motion support
- [ ] **Test:** all game-over states correct; visuals serif / saffron-gold / emoji-free

## Friend mode — compact v1 (built, needs deploy + device test)
Decisions: live moves over the **existing chat WebSocket**; **client-trusted** moves (server checks
turn ownership only). One active game per friendship.
- [x] Backend `ShantiSangha.Chess` module: `ChessGame` entity, create/get/move/resign endpoints,
  turn-ownership checks, realtime broadcast + push. **Builds clean; EF `InitChess` migration generated.**
- [x] `IRealtimeBroadcaster` in Shared (so Chess broadcasts over the chat hub without depending on Friends)
- [x] iOS `ChessAPI` + remote mode in `ChessGameViewModel` + `chess_*` kinds on `ChatRealtimeClient`
- [x] "Play chess" (♞) button in `FriendChatView` → `ChessPresenter.presentFriend(...)`
- [ ] **Deploy backend** (merging to `main` triggers it; `MigrateAsync` creates `ChessGames`) + device test two phones
- Deferred: server-side legality, draw offers, time controls, separate invite/accept flow, captured tray.

See [friend-mode-later.md](friend-mode-later.md) for the full/hardened design.
