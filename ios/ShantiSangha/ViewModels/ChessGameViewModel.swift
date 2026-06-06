import SwiftUI

/// Owns the authoritative game state and bridges the board scene to a
/// `ChessOpponent`. The scene is a pure renderer: it emits the user's completed
/// moves via `onMoveSelected`, the VM applies them, asks the opponent for a
/// reply, and pushes both back to the scene to animate.
///
/// The mode (difficulty / pass-and-play) is selectable on the game screen, so
/// the opponent is swappable — changing it starts a fresh game.
@MainActor
final class ChessGameViewModel: ObservableObject {

    @Published private(set) var position: ChessPosition = .standard
    @Published private(set) var result: GameResult?
    @Published private(set) var isOpponentThinking = false
    @Published private(set) var lastMove: ChessMove?
    @Published private(set) var mode: ChessMode

    /// The human always plays White (board oriented to White).
    let humanColor: PieceColor = .white
    private var opponent: ChessOpponent?

    /// Snapshots taken *before* each applied move, for undo.
    private var history: [(position: ChessPosition, lastMove: ChessMove?)] = []

    private weak var renderer: (any ChessBoardRenderer)?

    init(mode: ChessMode = .measured) {
        self.mode = mode
        self.opponent = mode.makeOpponent()
    }

    var isHotSeat: Bool { opponent == nil }
    var canUndo: Bool { !history.isEmpty && !isOpponentThinking }
    var isGameOver: Bool { result != nil }

    // MARK: Setup / mode

    func attach(renderer: any ChessBoardRenderer) {
        self.renderer = renderer
        renderer.onMoveSelected = { [weak self] move in
            self?.handleUserMove(move)
        }
        configureAndReset()
    }

    /// Switch mode (difficulty or pass-and-play) and start a fresh game.
    func select(mode: ChessMode) {
        self.mode = mode
        self.opponent = mode.makeOpponent()
        configureAndReset()
    }

    func newGame() { configureAndReset() }

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
        // If the opponent is on move first (not the case while human is White),
        // let it start.
        maybeTriggerOpponent()
    }

    // MARK: User / opponent moves

    private func handleUserMove(_ move: ChessMove) {
        guard result == nil, !isOpponentThinking else { return }
        apply(move, animate: true)
        maybeTriggerOpponent()
    }

    private func maybeTriggerOpponent() {
        guard let opponent, result == nil, position.sideToMove != humanColor else { return }
        isOpponentThinking = true
        refreshInteraction()
        let snapshot = position
        Task {
            let move = await opponent.move(for: snapshot)
            // Guard against a New Game / mode switch having changed the position.
            guard self.position == snapshot, self.result == nil else {
                self.isOpponentThinking = false
                self.refreshInteraction()
                return
            }
            self.isOpponentThinking = false
            if let move {
                self.apply(move, animate: true)
            }
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
        // In vs-computer mode, undo the AI reply *and* the human move; in
        // hot-seat undo a single ply.
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
        renderer?.isInteractionEnabled = (result == nil) && !isOpponentThinking
    }

    // MARK: Status text

    var statusText: String {
        if let result {
            switch result {
            case .checkmate(let winner):
                if isHotSeat { return "\(winner == .white ? "White" : "Black") wins by checkmate" }
                return winner == humanColor ? "Checkmate — you win" : "Checkmate — the app wins"
            case .stalemate: return "Stalemate — a draw"
            case .drawInsufficientMaterial: return "Draw — insufficient material"
            case .drawFiftyMove: return "Draw — fifty-move rule"
            case .drawRepetition: return "Draw — repetition"
            }
        }
        if isOpponentThinking { return "The app is considering…" }
        if position.isInCheck {
            let side = position.sideToMove
            if isHotSeat { return "\(side == .white ? "White" : "Black") is in check" }
            return side == humanColor ? "You are in check" : "The app is in check"
        }
        if isHotSeat { return position.sideToMove == .white ? "White to move" : "Black to move" }
        return position.sideToMove == humanColor ? "Your move" : "The app's move"
    }
}
