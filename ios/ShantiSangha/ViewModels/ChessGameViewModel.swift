import SwiftUI

/// Owns the authoritative game state and bridges the board scene to either a
/// local `ChessOpponent` (AI / hot-seat) or a remote friend (moves over the
/// chat WebSocket, persisted via `ChessAPI`). The scene stays a pure renderer.
@MainActor
final class ChessGameViewModel: ObservableObject {

    @Published private(set) var position: ChessPosition = .standard
    @Published private(set) var result: GameResult?
    @Published private(set) var isOpponentThinking = false
    @Published private(set) var lastMove: ChessMove?
    @Published private(set) var mode: ChessMode
    @Published private(set) var connectionError: String?

    /// The side the local player controls (board orientation + which pieces are
    /// movable). White for solo; assigned by the server for friend games.
    private(set) var humanColor: PieceColor = .white
    private var opponent: ChessOpponent?

    /// Friend-game config (nil for solo).
    struct FriendGame { let friendshipId: UUID; let friendUserId: UUID }
    private let friend: FriendGame?
    private var realtime: ChatRealtimeClient?
    private var remoteMoveCount = 0

    /// Snapshots taken *before* each applied move, for undo (solo only).
    private var history: [(position: ChessPosition, lastMove: ChessMove?)] = []

    private weak var renderer: (any ChessBoardRenderer)?

    init(mode: ChessMode = .measured) {
        self.mode = mode
        self.opponent = mode.makeOpponent()
        self.friend = nil
    }

    init(friend: FriendGame) {
        self.mode = .twoPlayer
        self.opponent = nil
        self.friend = friend
    }

    var isRemote: Bool { friend != nil }
    var isHotSeat: Bool { opponent == nil && !isRemote }
    var canUndo: Bool { !history.isEmpty && !isOpponentThinking && !isRemote }
    var isGameOver: Bool { result != nil }

    // MARK: Setup

    func attach(renderer: any ChessBoardRenderer) {
        self.renderer = renderer
        renderer.onMoveSelected = { [weak self] move in
            self?.handleUserMove(move)
        }
        if isRemote { setupRemote() } else { configureAndReset() }
    }

    /// Switch mode (solo difficulty / pass-and-play) and start a fresh game.
    func select(mode: ChessMode) {
        guard !isRemote else { return }
        self.mode = mode
        self.opponent = mode.makeOpponent()
        configureAndReset()
    }

    func newGame() {
        if isRemote { setupRemote() } else { configureAndReset() }
    }

    /// Disconnect the realtime socket (call from the view's onDisappear).
    func teardown() {
        realtime?.disconnect()
        realtime = nil
    }

    private func configureAndReset() {
        history.removeAll()
        position = .standard
        lastMove = nil
        result = nil
        isOpponentThinking = false
        renderer?.orientation = humanColor
        renderer?.interactionColor = isHotSeat ? nil : humanColor
        renderer?.show(position, animating: nil, lastMove: nil)
        refreshInteraction()
        maybeTriggerOpponent()
    }

    // MARK: Friend (remote) mode

    private func setupRemote() {
        guard let friend else { return }
        Task {
            do {
                let dto = try await ChessAPI.createOrGet(friendshipId: friend.friendshipId,
                                                         opponentUserId: friend.friendUserId)
                applyServerGame(dto)
                connectRealtime()
            } catch {
                connectionError = "Couldn't start the game."
            }
        }
    }

    private func applyServerGame(_ dto: ChessGameDTO) {
        guard let friend, let pos = ChessPosition(fen: dto.fen) else { return }
        // If white belongs to the friend, I'm black.
        humanColor = (dto.whiteUserId == friend.friendUserId) ? .black : .white
        remoteMoveCount = dto.moveCount
        position = pos
        lastMove = dto.lastMoveUci.flatMap(ChessMove.init(uci:))
        result = gameResult(fromStatus: dto.status)
        renderer?.orientation = humanColor
        renderer?.interactionColor = humanColor
        renderer?.show(pos, animating: nil, lastMove: lastMove)
        refreshInteraction()
    }

    private func connectRealtime() {
        guard let friend, realtime == nil else { return }
        Task {
            let baseURL = await ApiService.shared.getBaseURL()
            let client = ChatRealtimeClient(conversationId: friend.friendshipId, baseURL: baseURL,
                                            tokenProvider: { await ApiService.shared.currentToken() })
            client.onChessUpdate = { [weak self] fen, uci, status, moveCount in
                self?.applyRemoteUpdate(fen: fen, uci: uci, status: status, moveCount: moveCount)
            }
            self.realtime = client
            client.connect()
        }
    }

    private func applyRemoteUpdate(fen: String, uci: String?, status: String, moveCount: Int) {
        guard moveCount > remoteMoveCount else { return } // stale or our own echo
        remoteMoveCount = moveCount
        if let uci, let move = ChessMove(uci: uci), position.legalMoves().contains(move) {
            let (next, execution) = position.apply(move)
            position = next
            lastMove = move
            result = gameResult(fromStatus: status) ?? next.result()
            renderer?.show(next, animating: execution, lastMove: move)
        } else if let pos = ChessPosition(fen: fen) {
            position = pos
            lastMove = uci.flatMap(ChessMove.init(uci:))
            result = gameResult(fromStatus: status)
            renderer?.show(pos, animating: nil, lastMove: lastMove)
        }
        refreshInteraction()
    }

    func resign() {
        guard isRemote, let friend, result == nil else { return }
        Task {
            do { applyServerGame(try await ChessAPI.resign(friendshipId: friend.friendshipId)) }
            catch { connectionError = "Couldn't resign." }
        }
    }

    private func submitRemoteMove(_ move: ChessMove) {
        guard let friend else { return }
        let fen = position.fen
        let res = resultString(result)
        Task {
            do { _ = try await ChessAPI.move(friendshipId: friend.friendshipId, fen: fen, uci: move.uci, result: res) }
            catch { connectionError = "Move didn't reach your friend." }
        }
    }

    // MARK: User / opponent moves

    private func handleUserMove(_ move: ChessMove) {
        guard result == nil, !isOpponentThinking else { return }
        apply(move, animate: true)
        if isRemote {
            remoteMoveCount += 1
            submitRemoteMove(move)
        } else {
            maybeTriggerOpponent()
        }
    }

    private func maybeTriggerOpponent() {
        guard let opponent, result == nil, position.sideToMove != humanColor else { return }
        isOpponentThinking = true
        refreshInteraction()
        let snapshot = position
        Task {
            let move = await opponent.move(for: snapshot)
            guard self.position == snapshot, self.result == nil else {
                self.isOpponentThinking = false
                self.refreshInteraction()
                return
            }
            self.isOpponentThinking = false
            if let move { self.apply(move, animate: true) }
            self.refreshInteraction()
        }
    }

    private func apply(_ move: ChessMove, animate: Bool) {
        history.append((position, lastMove))
        let (next, execution) = position.apply(move)
        position = next
        lastMove = move
        result = next.result()
        renderer?.show(next, animating: animate ? execution : nil, lastMove: move)
        refreshInteraction()
    }

    // MARK: Controls

    func undo() {
        guard canUndo else { return }
        let steps = isHotSeat ? 1 : 2
        var restored: (position: ChessPosition, lastMove: ChessMove?)?
        for _ in 0..<steps {
            if let snap = history.popLast() { restored = snap }
        }
        guard let restored else { return }
        position = restored.position
        lastMove = restored.lastMove
        result = nil
        renderer?.show(position, animating: nil, lastMove: lastMove)
        refreshInteraction()
    }

    private func refreshInteraction() {
        // In friend mode you can only move on your turn; the renderer already
        // restricts to `humanColor`, and game-over disables interaction.
        renderer?.isInteractionEnabled = (result == nil) && !isOpponentThinking
    }

    // MARK: Mapping helpers

    private func resultString(_ r: GameResult?) -> String? {
        switch r {
        case .checkmate: return "checkmate"
        case .stalemate: return "stalemate"
        case .drawInsufficientMaterial, .drawFiftyMove, .drawRepetition: return "draw"
        case nil: return nil
        }
    }

    private func gameResult(fromStatus status: String) -> GameResult? {
        switch status {
        case "WhiteWon": return .checkmate(winner: .white)
        case "BlackWon": return .checkmate(winner: .black)
        case "Draw": return .stalemate
        default: return nil
        }
    }

    // MARK: Status text

    var statusText: String {
        if let result {
            switch result {
            case .checkmate(let winner):
                if isHotSeat { return "\(winner == .white ? "White" : "Black") wins by checkmate" }
                if isRemote { return winner == humanColor ? "You win" : "You lose" }
                return winner == humanColor ? "Checkmate — you win" : "Checkmate — the app wins"
            case .stalemate: return "Stalemate — a draw"
            case .drawInsufficientMaterial: return "Draw — insufficient material"
            case .drawFiftyMove: return "Draw — fifty-move rule"
            case .drawRepetition: return "Draw — repetition"
            }
        }
        if isOpponentThinking { return "The app is considering…" }
        let side = position.sideToMove
        if position.isInCheck {
            if isHotSeat { return "\(side == .white ? "White" : "Black") is in check" }
            if isRemote { return side == humanColor ? "You are in check" : "Your friend is in check" }
            return side == humanColor ? "You are in check" : "The app is in check"
        }
        if isHotSeat { return side == .white ? "White to move" : "Black to move" }
        if isRemote { return side == humanColor ? "Your move" : "Your friend's move" }
        return side == humanColor ? "Your move" : "The app's move"
    }
}
