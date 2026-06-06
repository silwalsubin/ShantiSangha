# Friend Mode

**Compact v1 is built** (see PROGRESS.md). Live moves ride the existing chat WebSocket; the server
trusts the client for legality and checks only turn ownership. What shipped vs. the full design below:

**Built (compact v1):**
- Backend `ShantiSangha.Chess` module — `ChessGame` keyed to a friendship; endpoints
  `POST /api/chess/games`, `GET /api/chess/games/{friendshipId}`, `POST .../moves`, `POST .../resign`.
  Broadcasts `chess_move` / `chess_game_over` / `chess_game_created` over the chat hub
  (channel = friendship id) via the new Shared `IRealtimeBroadcaster`; pushes the opponent.
  Stores only the latest FEN + last move (no per-move table).
- iOS — `ChessAPI`, remote mode in `ChessGameViewModel` (loads/creates the game, submits moves,
  applies opponent moves from `ChatRealtimeClient.onChessUpdate`), "Play chess" entry in `FriendChatView`.

**Manual step to go live:** merge to `main` → backend deploy runs `MigrateAsync` (creates `ChessGames`).

**Deferred / hardening (the original full design follows):** server-side legality, draw offers,
time controls, separate invite/accept flow, per-move history, captured-pieces tray.

---

The original full design (for hardening) — the app's existing infrastructure makes this largely
*assembly*, not new plumbing.

## Backend — new `ShantiSangha.Chess` module
A new project in the modular monolith (mirrors `ShantiSangha.Friends`):
- **Entities** (own `ChessDbContext`, explicit `.ToTable()`):
  - `ChessGame`: id, friendshipId, whitePlayerUserId, blackPlayerUserId, fen, sideToMove,
    status (pending/active/checkmate/stalemate/resigned/draw), winnerUserId, drawOfferBy, timestamps
  - `ChessMove`: id, gameId, ply, fromSquare, toSquare, uci, san, fenAfter, createdAt
- **`ChessGameService`** with **server-authoritative** move validation behind an `IChessEngine`
  (vetted C# chess library). `SubmitMoveAsync`: load → verify turn → validate legality → persist →
  detect terminal → broadcast + push. Mirrors
  `backend/ShantiSangha.Friends/Services/FriendMessagesService.cs`.
- REST controller, EF `InitChess` migration, `AddChessModule(connStr)` DI wiring in
  `backend/ShantiSangha.Api/Program.cs` + `.AddApplicationPart(...)`.

## Realtime + push reuse
- Broadcast new kinds (`chess_game_created` / `chess_move` / `chess_draw_offered` /
  `chess_game_over`) over the existing `RedisChatRealtimeHub.PublishAsync(friendshipId, kind, payload)`.
- "Your turn" push via `IPushNotificationService.SendAlertPushAsync(opponentId, ..., data:{type:"chess_move", friendshipId, gameId})`.
- A game binds 1:1 to a friendship (`conversationId == friendshipId`).

## iOS additions
- `RemoteOpponent : ChessOpponent` — submits move via `Services/ChessAPI.swift`, surfaces the
  friend's move via `Services/ChessRealtimeClient.swift` (mirror `ChatRealtimeClient`).
- `DeepLinkRouter` route for `chess_move` / `chess_game_over`; push handler in `ShantiSanghaApp.swift`.
- A "Play" entry in `Views/Friends/FriendChatView`; friend games listed in `ChessHomeView`.
- Offline moves via `SyncService` queue; reconcile against `GET game` on reconnect (server wins).
- **The board scene + rules + ViewModel carry over unchanged** thanks to the `ChessOpponent` seam.

## Key decisions to revisit when building
- **Module boundary:** `IChatRealtimeHub` currently lives in `ShantiSangha.Friends`; the modular
  rule forbids `Chess → Friends`. Move the hub interface (ideally `RedisChatRealtimeHub` + WS
  endpoint too) into `ShantiSangha.Shared` or a new `ShantiSangha.Realtime` project.
- **Server is authoritative**; the client sends only the intended move. Optimistic UI reconciles to
  server truth on rejection/divergence.
- One active game per friendship for V1 (partial-unique index + guard).
