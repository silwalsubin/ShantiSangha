# Phase 3 — Polish

**Goal:** make the solo experience feel finished and on-brand.

## Tasks
1. **Check indicator** — subtle highlight of the king in check.
2. **Last-move highlight** — mark the from/to squares of the most recent move.
3. **Game-over overlay** — result (Checkmate / Stalemate / Draw) + **New Game**, in the app's style.
4. **Optional undo** — take back the last full move (user + AI reply).
5. **Optional persistence** — save a single in-progress game to disk so it survives app restart;
   reuse the lightweight JSON-file pattern from `ios/ShantiSangha/Services/ChatCache.swift`.
6. **Haptics** — CoreHaptics feedback on move / capture (respect system settings).
7. **Reduce Motion** — fall back to instant/cross-fade piece movement when enabled.

## Visual overhaul (added 2026-06-06 — user wanted a premium, "top-notch" feel)
Done in code (needs device verification):
- [x] Full-screen immersive layout — tab bar hidden, board centered & large
- [x] Walnut/ivory **gradient tiles** with bevel (Core Graphics textures)
- [x] Framed board with rounded corners + drop shadow + coordinate labels
- [x] **Pieces rendered to textures** with drop shadow + filled/outlined glyph (depth, not flat)
- [x] **Lift-on-select** (scale + rise + grown contact shadow), **landing squash-and-stretch**
- [x] **Sparkle burst** (SKEmitter) on capture; pulsing legal-move markers; **pulsing red check glow**
- [x] Game-over overlay card with **Rematch** + Leave
- [x] Haptics: light on select/land, medium on move, rigid on capture
- [x] Reduce Motion respected (moves snap)

Still open / optional:
- [ ] **Drag-to-move** (currently tap-to-select → tap-to-move only)
- [ ] Captured-pieces tray (needs VM to accumulate captures)
- [ ] Persist in-progress game across launches
- [ ] If true **3D** pieces are wanted: SceneKit/RealityKit + 3D model assets (separate pipeline)

## Acceptance checks
- [ ] All game-over states reach the overlay; Rematch resets cleanly
- [ ] Undo restores the prior position correctly
- [ ] Pieces render crisp (Apple Symbols glyph font) with visible depth/shadow
- [ ] Animations feel smooth; capture sparkle + check pulse fire
- [ ] Reduce Motion snaps moves
- [ ] Visuals stay warm/saffron, serif, emoji-free
