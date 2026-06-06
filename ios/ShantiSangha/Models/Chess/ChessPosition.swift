import Foundation

/// Immutable-by-convention chess position. Mutating helpers return a new
/// position so the game layer can keep a history for undo / repetition.
///
/// Correctness notes (verify on first device build): castling checks that the
/// king is not in check and does not pass through or land on an attacked
/// square; en passant is only legal on the move immediately after the enemy
/// double-push; promotion generates all four piece choices.
struct ChessPosition: Hashable, Codable {
    /// 64 squares, index 0 = a1 ... 63 = h8.
    var board: [Piece?]
    var sideToMove: PieceColor
    var castling: CastlingRights
    var enPassant: Square?
    var halfmoveClock: Int
    var fullmoveNumber: Int

    // MARK: Construction

    init(board: [Piece?], sideToMove: PieceColor, castling: CastlingRights,
         enPassant: Square?, halfmoveClock: Int, fullmoveNumber: Int) {
        precondition(board.count == 64, "Board must have 64 squares")
        self.board = board
        self.sideToMove = sideToMove
        self.castling = castling
        self.enPassant = enPassant
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    /// Standard starting position.
    static var standard: ChessPosition {
        // swiftlint:disable:next force_unwrapping
        ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")!
    }

    func piece(at square: Square) -> Piece? { board[square.index] }

    // MARK: FEN

    /// Parse a full FEN string. Returns nil on malformed input.
    init?(fen: String) {
        let parts = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4 else { return nil }

        // 1. Piece placement (rank 8 first).
        var squares = [Piece?](repeating: nil, count: 64)
        let ranks = parts[0].split(separator: "/").map(String.init)
        guard ranks.count == 8 else { return nil }
        for (rowFromTop, rankStr) in ranks.enumerated() {
            let rank = 7 - rowFromTop
            var file = 0
            for ch in rankStr {
                if let digit = ch.wholeNumberValue {
                    file += digit
                } else if let piece = Piece(fenCharacter: ch) {
                    guard file < 8 else { return nil }
                    squares[rank * 8 + file] = piece
                    file += 1
                } else {
                    return nil
                }
            }
            guard file == 8 else { return nil }
        }

        // 2. Side to move.
        let side: PieceColor = parts[1] == "w" ? .white : (parts[1] == "b" ? .black : .white)

        // 3. Castling rights.
        var rights = CastlingRights.none
        if parts[2] != "-" {
            for ch in parts[2] {
                switch ch {
                case "K": rights.whiteKingside = true
                case "Q": rights.whiteQueenside = true
                case "k": rights.blackKingside = true
                case "q": rights.blackQueenside = true
                default: break
                }
            }
        }

        // 4. En passant target.
        let ep = parts[3] == "-" ? nil : Square(algebraic: parts[3])

        // 5/6. Clocks (optional).
        let half = parts.count > 4 ? (Int(parts[4]) ?? 0) : 0
        let full = parts.count > 5 ? (Int(parts[5]) ?? 1) : 1

        self.init(board: squares, sideToMove: side, castling: rights,
                  enPassant: ep, halfmoveClock: half, fullmoveNumber: full)
    }

    /// Serialize back to FEN.
    var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(piece.fenCharacter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        let placement = rows.joined(separator: "/")
        let side = sideToMove == .white ? "w" : "b"
        var castle = ""
        if castling.whiteKingside { castle += "K" }
        if castling.whiteQueenside { castle += "Q" }
        if castling.blackKingside { castle += "k" }
        if castling.blackQueenside { castle += "q" }
        if castle.isEmpty { castle = "-" }
        let ep = enPassant?.algebraic ?? "-"
        return "\(placement) \(side) \(castle) \(ep) \(halfmoveClock) \(fullmoveNumber)"
    }

    // MARK: Attack detection

    /// Is `square` attacked by any piece of `color`?
    func isSquareAttacked(_ square: Square, by color: PieceColor) -> Bool {
        let f = square.file, r = square.rank

        // Pawn attacks: a pawn of `color` attacks "forward" diagonally.
        let pawnRankOffset = color == .white ? -1 : 1
        for df in [-1, 1] {
            if let s = Square(file: f + df, rank: r + pawnRankOffset),
               let p = board[s.index], p.color == color, p.type == .pawn {
                return true
            }
        }

        // Knight attacks.
        let knightDeltas = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
        for (df, dr) in knightDeltas {
            if let s = Square(file: f + df, rank: r + dr),
               let p = board[s.index], p.color == color, p.type == .knight {
                return true
            }
        }

        // King adjacency.
        for df in -1...1 {
            for dr in -1...1 where !(df == 0 && dr == 0) {
                if let s = Square(file: f + df, rank: r + dr),
                   let p = board[s.index], p.color == color, p.type == .king {
                    return true
                }
            }
        }

        // Sliding: bishops/queens on diagonals, rooks/queens on files/ranks.
        let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        if rayHitsAttacker(from: square, directions: diagonal, color: color, types: [.bishop, .queen]) {
            return true
        }
        if rayHitsAttacker(from: square, directions: straight, color: color, types: [.rook, .queen]) {
            return true
        }
        return false
    }

    private func rayHitsAttacker(from square: Square, directions: [(Int, Int)],
                                 color: PieceColor, types: Set<PieceType>) -> Bool {
        for (df, dr) in directions {
            var file = square.file + df
            var rank = square.rank + dr
            while let s = Square(file: file, rank: rank) {
                if let p = board[s.index] {
                    if p.color == color, types.contains(p.type) { return true }
                    break // blocked by any piece
                }
                file += df
                rank += dr
            }
        }
        return false
    }

    /// Square of `color`'s king, or nil if absent (shouldn't happen in legal play).
    func kingSquare(_ color: PieceColor) -> Square? {
        for sq in Square.allSquares where board[sq.index] == Piece(color: color, type: .king) {
            return sq
        }
        return nil
    }

    /// Is the side to move currently in check?
    var isInCheck: Bool {
        guard let king = kingSquare(sideToMove) else { return false }
        return isSquareAttacked(king, by: sideToMove.opposite)
    }

    func isInCheck(_ color: PieceColor) -> Bool {
        guard let king = kingSquare(color) else { return false }
        return isSquareAttacked(king, by: color.opposite)
    }

    // MARK: Move generation

    /// All fully-legal moves for the side to move.
    func legalMoves() -> [ChessMove] {
        pseudoLegalMoves().filter { isLegal($0) }
    }

    /// Legal moves originating from a specific square (for highlighting).
    func legalMoves(from square: Square) -> [ChessMove] {
        legalMoves().filter { $0.from == square }
    }

    /// A move is legal if, after making it, the mover's king is not attacked.
    func isLegal(_ move: ChessMove) -> Bool {
        guard let piece = board[move.from.index], piece.color == sideToMove else { return false }
        let next = applyUnchecked(move).0
        // After applyUnchecked, sideToMove has flipped; check the mover's king.
        return !next.isInCheck(piece.color)
    }

    /// Pseudo-legal moves (ignores leaving own king in check). Castling here
    /// already verifies the king is not in/through/into check, since that is
    /// awkward to express as a post-move king-safety test.
    private func pseudoLegalMoves() -> [ChessMove] {
        var moves: [ChessMove] = []
        for sq in Square.allSquares {
            guard let piece = board[sq.index], piece.color == sideToMove else { continue }
            switch piece.type {
            case .pawn: appendPawnMoves(from: sq, into: &moves)
            case .knight: appendStepMoves(from: sq, deltas: Self.knightDeltas, into: &moves)
            case .king:
                appendStepMoves(from: sq, deltas: Self.kingDeltas, into: &moves)
                appendCastling(from: sq, into: &moves)
            case .bishop: appendSlidingMoves(from: sq, directions: Self.diagonalDirs, into: &moves)
            case .rook: appendSlidingMoves(from: sq, directions: Self.straightDirs, into: &moves)
            case .queen: appendSlidingMoves(from: sq, directions: Self.diagonalDirs + Self.straightDirs, into: &moves)
            }
        }
        return moves
    }

    private static let knightDeltas = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingDeltas = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let diagonalDirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let straightDirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    private func appendStepMoves(from sq: Square, deltas: [(Int, Int)], into moves: inout [ChessMove]) {
        for (df, dr) in deltas {
            guard let target = Square(file: sq.file + df, rank: sq.rank + dr) else { continue }
            if let occupant = board[target.index], occupant.color == sideToMove { continue }
            moves.append(ChessMove(from: sq, to: target))
        }
    }

    private func appendSlidingMoves(from sq: Square, directions: [(Int, Int)], into moves: inout [ChessMove]) {
        for (df, dr) in directions {
            var file = sq.file + df
            var rank = sq.rank + dr
            while let target = Square(file: file, rank: rank) {
                if let occupant = board[target.index] {
                    if occupant.color != sideToMove { moves.append(ChessMove(from: sq, to: target)) }
                    break
                }
                moves.append(ChessMove(from: sq, to: target))
                file += df
                rank += dr
            }
        }
    }

    private func appendPawnMoves(from sq: Square, into moves: inout [ChessMove]) {
        let dir = sideToMove == .white ? 1 : -1
        let startRank = sideToMove == .white ? 1 : 6
        let promoRank = sideToMove == .white ? 7 : 0

        // Single push.
        if let one = Square(file: sq.file, rank: sq.rank + dir), board[one.index] == nil {
            appendPawnDestination(from: sq, to: one, promoRank: promoRank, into: &moves)
            // Double push.
            if sq.rank == startRank,
               let two = Square(file: sq.file, rank: sq.rank + 2 * dir),
               board[two.index] == nil {
                moves.append(ChessMove(from: sq, to: two))
            }
        }

        // Captures (including en passant).
        for df in [-1, 1] {
            guard let target = Square(file: sq.file + df, rank: sq.rank + dir) else { continue }
            if let occupant = board[target.index], occupant.color != sideToMove {
                appendPawnDestination(from: sq, to: target, promoRank: promoRank, into: &moves)
            } else if target == enPassant {
                moves.append(ChessMove(from: sq, to: target))
            }
        }
    }

    private func appendPawnDestination(from: Square, to: Square, promoRank: Int, into moves: inout [ChessMove]) {
        if to.rank == promoRank {
            for promo in [PieceType.queen, .rook, .bishop, .knight] {
                moves.append(ChessMove(from: from, to: to, promotion: promo))
            }
        } else {
            moves.append(ChessMove(from: from, to: to))
        }
    }

    private func appendCastling(from sq: Square, into moves: inout [ChessMove]) {
        let backRank = sideToMove == .white ? 0 : 7
        guard sq == Square(file: 4, rank: backRank) else { return }
        guard !isSquareAttacked(sq, by: sideToMove.opposite) else { return } // not in check

        let kingside = sideToMove == .white ? castling.whiteKingside : castling.blackKingside
        let queenside = sideToMove == .white ? castling.whiteQueenside : castling.blackQueenside

        if kingside {
            let f5 = Square(file: 5, rank: backRank)!
            let f6 = Square(file: 6, rank: backRank)!
            if board[f5.index] == nil, board[f6.index] == nil,
               !isSquareAttacked(f5, by: sideToMove.opposite),
               !isSquareAttacked(f6, by: sideToMove.opposite) {
                moves.append(ChessMove(from: sq, to: f6))
            }
        }
        if queenside {
            let d = Square(file: 3, rank: backRank)!
            let c = Square(file: 2, rank: backRank)!
            let b = Square(file: 1, rank: backRank)!
            if board[d.index] == nil, board[c.index] == nil, board[b.index] == nil,
               !isSquareAttacked(d, by: sideToMove.opposite),
               !isSquareAttacked(c, by: sideToMove.opposite) {
                moves.append(ChessMove(from: sq, to: c))
            }
        }
    }

    // MARK: Applying moves

    /// Apply a legal move, returning the new position and an execution
    /// description for animation. Caller is responsible for legality (use
    /// `isLegal` / `legalMoves`).
    func apply(_ move: ChessMove) -> (ChessPosition, MoveExecution) {
        applyUnchecked(move)
    }

    private func applyUnchecked(_ move: ChessMove) -> (ChessPosition, MoveExecution) {
        var next = self
        guard let moving = board[move.from.index] else {
            // Shouldn't happen; return unchanged with a no-op execution.
            return (self, MoveExecution(move: move, capturedSquare: nil, capturedPiece: nil,
                                        rookFrom: nil, rookTo: nil, isEnPassant: false, promotedTo: nil))
        }

        var capturedSquare: Square?
        var capturedPiece: Piece?
        var rookFrom: Square?
        var rookTo: Square?
        var isEnPassant = false

        // En passant capture: the taken pawn is behind the destination square.
        if moving.type == .pawn, move.to == enPassant, board[move.to.index] == nil {
            isEnPassant = true
            let capRank = move.from.rank // captured pawn sits on the mover's rank
            if let capSq = Square(file: move.to.file, rank: capRank) {
                capturedSquare = capSq
                capturedPiece = board[capSq.index]
                next.board[capSq.index] = nil
            }
        } else if let occupant = board[move.to.index] {
            capturedSquare = move.to
            capturedPiece = occupant
        }

        // Move the piece (apply promotion if any).
        next.board[move.from.index] = nil
        if let promo = move.promotion {
            next.board[move.to.index] = Piece(color: moving.color, type: promo)
        } else {
            next.board[move.to.index] = moving
        }

        // Castling: relocate the rook when the king steps two files.
        if moving.type == .king, abs(move.to.file - move.from.file) == 2 {
            let backRank = move.from.rank
            if move.to.file == 6 { // kingside
                let rf = Square(file: 7, rank: backRank)!
                let rt = Square(file: 5, rank: backRank)!
                next.board[rt.index] = next.board[rf.index]
                next.board[rf.index] = nil
                rookFrom = rf; rookTo = rt
            } else if move.to.file == 2 { // queenside
                let rf = Square(file: 0, rank: backRank)!
                let rt = Square(file: 3, rank: backRank)!
                next.board[rt.index] = next.board[rf.index]
                next.board[rf.index] = nil
                rookFrom = rf; rookTo = rt
            }
        }

        // Update castling rights when kings/rooks move or rooks are captured.
        next.updateCastlingRights(moving: moving, move: move, capturedPiece: capturedPiece, capturedSquare: capturedSquare)

        // En passant target: only set on a double pawn push.
        if moving.type == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            let midRank = (move.to.rank + move.from.rank) / 2
            next.enPassant = Square(file: move.from.file, rank: midRank)
        } else {
            next.enPassant = nil
        }

        // Halfmove clock: reset on pawn move or capture, else increment.
        if moving.type == .pawn || capturedPiece != nil {
            next.halfmoveClock = 0
        } else {
            next.halfmoveClock += 1
        }

        if sideToMove == .black { next.fullmoveNumber += 1 }
        next.sideToMove = sideToMove.opposite

        let execution = MoveExecution(move: move, capturedSquare: capturedSquare,
                                      capturedPiece: capturedPiece, rookFrom: rookFrom,
                                      rookTo: rookTo, isEnPassant: isEnPassant,
                                      promotedTo: move.promotion)
        return (next, execution)
    }

    private mutating func updateCastlingRights(moving: Piece, move: ChessMove,
                                               capturedPiece: Piece?, capturedSquare: Square?) {
        if moving.type == .king {
            if moving.color == .white { castling.whiteKingside = false; castling.whiteQueenside = false }
            else { castling.blackKingside = false; castling.blackQueenside = false }
        }
        // A rook leaving its home square forfeits that side's right.
        func clearForRookSquare(_ sq: Square) {
            switch (sq.file, sq.rank) {
            case (0, 0): castling.whiteQueenside = false
            case (7, 0): castling.whiteKingside = false
            case (0, 7): castling.blackQueenside = false
            case (7, 7): castling.blackKingside = false
            default: break
            }
        }
        if moving.type == .rook { clearForRookSquare(move.from) }
        if capturedPiece?.type == .rook, let cap = capturedSquare { clearForRookSquare(cap) }
    }

    // MARK: Game result

    /// Terminal result if the game is over, else nil.
    func result() -> GameResult? {
        if legalMoves().isEmpty {
            return isInCheck ? .checkmate(winner: sideToMove.opposite) : .stalemate
        }
        if halfmoveClock >= 100 { return .drawFiftyMove }
        if hasInsufficientMaterial { return .drawInsufficientMaterial }
        return nil
    }

    /// K vs K, K+minor vs K, and K+B vs K+B with same-colored bishops.
    var hasInsufficientMaterial: Bool {
        var minors: [(color: PieceColor, square: Square)] = []
        for sq in Square.allSquares {
            guard let p = board[sq.index] else { continue }
            switch p.type {
            case .king: continue
            case .bishop, .knight: minors.append((p.color, sq))
            default: return false // pawn/rook/queen present → sufficient
            }
        }
        if minors.isEmpty { return true } // K vs K
        if minors.count == 1 { return true } // K+minor vs K
        if minors.count == 2 {
            // Two bishops on same color complex (one each side or same side) → draw.
            let allBishops = minors.allSatisfy { board[$0.square.index]?.type == .bishop }
            if allBishops {
                let colors = Set(minors.map { ($0.square.file + $0.square.rank) % 2 })
                return colors.count == 1
            }
        }
        return false
    }
}
