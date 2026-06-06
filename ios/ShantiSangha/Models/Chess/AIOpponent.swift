import Foundation
import GameplayKit

/// The computer opponent. Wraps the pure-Swift `ChessPosition` in GameplayKit's
/// `GKGameModel` abstraction and lets `GKMinmaxStrategist` (alpha-beta) pick a
/// move. The search runs on a background queue so the board stays responsive.
struct AIOpponent: ChessOpponent {
    let difficulty: ChessDifficulty

    func move(for position: ChessPosition) async -> ChessMove? {
        let depth = difficulty.lookAheadDepth
        let chosen: ChessMove? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let model = ChessGameModel(position: position)
                let strategist = GKMinmaxStrategist()
                strategist.maxLookAheadDepth = depth
                // A random source makes the AI vary between equally-scored moves
                // so games aren't identical every time.
                strategist.randomSource = GKARC4RandomSource()
                strategist.gameModel = model

                let move = (strategist.bestMoveForActivePlayer() as? ChessMoveUpdate)?.move
                    ?? position.legalMoves().randomElement() // safety net
                continuation.resume(returning: move)
            }
        }
        // A deliberate pause so the reply feels considered, not instant. Easy
        // levels (which compute almost instantly) get the full pause; harder
        // levels already spend real time searching, so this just rounds it out.
        let pause = Double.random(in: difficulty.thinkPause)
        try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
        return chosen
    }
}

// MARK: - GameplayKit adapters

/// A GameplayKit player keyed by chess color (white = 0, black = 1).
final class ChessGameModelPlayer: NSObject, GKGameModelPlayer {
    let playerId: Int
    let color: PieceColor

    private init(color: PieceColor) {
        self.color = color
        self.playerId = color == .white ? 0 : 1
        super.init()
    }

    static let white = ChessGameModelPlayer(color: .white)
    static let black = ChessGameModelPlayer(color: .black)
    static func player(for color: PieceColor) -> ChessGameModelPlayer {
        color == .white ? white : black
    }
}

/// A candidate move wrapped for GameplayKit. `value` is unused by the
/// strategist (it scores via the game model) but required by the protocol.
final class ChessMoveUpdate: NSObject, GKGameModelUpdate {
    var value: Int = 0
    let move: ChessMove
    init(_ move: ChessMove) { self.move = move }
}

/// Bridges `ChessPosition` to GameplayKit's minimax engine.
final class ChessGameModel: NSObject, GKGameModel {
    var position: ChessPosition

    init(position: ChessPosition) {
        self.position = position
        super.init()
    }

    var players: [GKGameModelPlayer]? { [ChessGameModelPlayer.white, ChessGameModelPlayer.black] }

    var activePlayer: GKGameModelPlayer? { ChessGameModelPlayer.player(for: position.sideToMove) }

    func setGameModel(_ gameModel: GKGameModel) {
        if let other = gameModel as? ChessGameModel { position = other.position }
    }

    func copy(with zone: NSZone? = nil) -> Any {
        ChessGameModel(position: position)
    }

    func gameModelUpdates(for player: GKGameModelPlayer) -> [GKGameModelUpdate]? {
        guard let p = player as? ChessGameModelPlayer, p.color == position.sideToMove else { return [] }
        return position.legalMoves().map(ChessMoveUpdate.init)
    }

    func apply(_ gameModelUpdate: GKGameModelUpdate) {
        guard let update = gameModelUpdate as? ChessMoveUpdate else { return }
        position = position.apply(update.move).0
    }

    func score(for player: GKGameModelPlayer) -> Int {
        guard let p = player as? ChessGameModelPlayer else { return 0 }
        return Self.evaluate(position, for: p.color)
    }

    func isWin(for player: GKGameModelPlayer) -> Bool {
        guard let p = player as? ChessGameModelPlayer else { return false }
        if case .checkmate(let winner) = position.result() { return winner == p.color }
        return false
    }

    func isLoss(for player: GKGameModelPlayer) -> Bool {
        guard let p = player as? ChessGameModelPlayer else { return false }
        if case .checkmate(let winner) = position.result() { return winner == p.color.opposite }
        return false
    }

    /// Material balance (centipawns) from `color`'s perspective, with a tiny
    /// mobility nudge so the AI develops rather than shuffling.
    private static func evaluate(_ position: ChessPosition, for color: PieceColor) -> Int {
        if case .checkmate(let winner) = position.result() {
            return winner == color ? 100_000 : -100_000
        }
        var material = 0
        for sq in Square.allSquares {
            guard let piece = position.board[sq.index] else { continue }
            let value = piece.type.materialValue
            material += piece.color == color ? value : -value
        }
        let mobility = position.legalMoves().count
        let mobilityScore = position.sideToMove == color ? mobility : -mobility
        return material + mobilityScore
    }
}
