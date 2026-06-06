import Foundation

// MARK: - Core chess value types
//
// A small, self-contained chess model. No external dependency: everything the
// app needs (legality, check/mate/stalemate, FEN, move generation) lives in
// `ChessPosition`. These types are intentionally simple value types so the
// game state can be copied and diffed cheaply for animation.

/// Side to move / piece owner.
enum PieceColor: String, Hashable, Codable {
    case white, black

    var opposite: PieceColor { self == .white ? .black : .white }
}

/// The six piece kinds.
enum PieceType: String, Hashable, Codable, CaseIterable {
    case pawn, knight, bishop, rook, queen, king

    /// Lowercase letter used in FEN (color applied by the board).
    var fenLetter: Character {
        switch self {
        case .pawn: return "p"
        case .knight: return "n"
        case .bishop: return "b"
        case .rook: return "r"
        case .queen: return "q"
        case .king: return "k"
        }
    }

    /// Rough material value used by the AI evaluation (kings excluded from scoring).
    var materialValue: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 0
        }
    }
}

/// A colored piece sitting on a square.
struct Piece: Hashable, Codable {
    let color: PieceColor
    let type: PieceType

    /// FEN character: uppercase for white, lowercase for black.
    var fenCharacter: Character {
        let base = type.fenLetter
        return color == .white ? Character(base.uppercased()) : base
    }

    init(color: PieceColor, type: PieceType) {
        self.color = color
        self.type = type
    }

    /// Parse a single FEN piece character (e.g. "N" = white knight).
    init?(fenCharacter: Character) {
        let color: PieceColor = fenCharacter.isUppercase ? .white : .black
        switch Character(fenCharacter.lowercased()) {
        case "p": self = Piece(color: color, type: .pawn)
        case "n": self = Piece(color: color, type: .knight)
        case "b": self = Piece(color: color, type: .bishop)
        case "r": self = Piece(color: color, type: .rook)
        case "q": self = Piece(color: color, type: .queen)
        case "k": self = Piece(color: color, type: .king)
        default: return nil
        }
    }
}

/// A board square, indexed 0...63 where 0 = a1 and 63 = h8.
/// `file` is 0...7 (a-h), `rank` is 0...7 (rank 1 = 0).
struct Square: Hashable, Codable, CustomStringConvertible {
    let index: Int

    init(index: Int) { self.index = index }

    /// Returns nil when file/rank fall off the board — used by move generation.
    init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.index = rank * 8 + file
    }

    var file: Int { index % 8 }
    var rank: Int { index / 8 }

    /// e.g. "e4".
    var algebraic: String {
        let fileChar = Character(UnicodeScalar(UInt8(97 + file)))
        return "\(fileChar)\(rank + 1)"
    }

    /// Parse algebraic coordinate like "e4".
    init?(algebraic: String) {
        let chars = Array(algebraic.lowercased())
        guard chars.count == 2,
              let fileAscii = chars[0].asciiValue,
              let rankDigit = chars[1].wholeNumberValue else { return nil }
        let file = Int(fileAscii) - 97
        let rank = rankDigit - 1
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.index = rank * 8 + file
    }

    var description: String { algebraic }

    static let allSquares: [Square] = (0..<64).map(Square.init(index:))
}

/// A move from one square to another, with an optional promotion piece.
/// Castling is encoded as the king's two-square move; en passant as the
/// capturing pawn's diagonal move to the empty target square.
struct ChessMove: Hashable, Codable {
    let from: Square
    let to: Square
    let promotion: PieceType?

    init(from: Square, to: Square, promotion: PieceType? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// UCI long algebraic, e.g. "e2e4" or "e7e8q".
    var uci: String {
        var s = from.algebraic + to.algebraic
        if let promotion { s.append(promotion.fenLetter) }
        return s
    }
}

/// Castling availability, mirrored from FEN's KQkq field.
struct CastlingRights: Hashable, Codable {
    var whiteKingside = false
    var whiteQueenside = false
    var blackKingside = false
    var blackQueenside = false

    static let none = CastlingRights()
    static let all = CastlingRights(whiteKingside: true, whiteQueenside: true,
                                    blackKingside: true, blackQueenside: true)
}

/// Terminal game results plus draw conditions.
enum GameResult: Equatable {
    case checkmate(winner: PieceColor)
    case stalemate
    case drawInsufficientMaterial
    case drawFiftyMove
    case drawRepetition

    var isDraw: Bool {
        switch self {
        case .checkmate: return false
        default: return true
        }
    }
}

/// Describes the concrete effects of applying a move, so the SpriteKit scene
/// can animate captures / castling / en passant / promotion precisely.
struct MoveExecution {
    let move: ChessMove
    /// Square a piece was removed from (en passant differs from `move.to`).
    let capturedSquare: Square?
    let capturedPiece: Piece?
    /// For castling: the rook's from/to squares (nil otherwise).
    let rookFrom: Square?
    let rookTo: Square?
    let isEnPassant: Bool
    let promotedTo: PieceType?
}
