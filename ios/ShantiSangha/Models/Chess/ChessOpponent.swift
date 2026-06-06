import Foundation

/// Abstracts where the reply move comes from. `AIOpponent` is the only
/// implementation today; friend mode would add a networked `RemoteOpponent`
/// without the board or ViewModel changing. See architecture.md.
protocol ChessOpponent {
    /// Choose a move for the given position. Async so a compute-heavy (or, later,
    /// networked) opponent never blocks the main actor / UI.
    func move(for position: ChessPosition) async -> ChessMove?
}

/// A selectable game mode shown as chips on the board screen: three vs-computer
/// difficulties plus pass-and-play. Drives which `ChessOpponent` (if any) the
/// game uses.
enum ChessMode: String, CaseIterable, Identifiable {
    case gentle, measured, sharp, twoPlayer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: return "Gentle"
        case .measured: return "Measured"
        case .sharp: return "Sharp"
        case .twoPlayer: return "2 Players"
        }
    }

    /// nil for pass-and-play (no computer opponent).
    var difficulty: ChessDifficulty? {
        switch self {
        case .gentle: return .easy
        case .measured: return .medium
        case .sharp: return .hard
        case .twoPlayer: return nil
        }
    }

    func makeOpponent() -> ChessOpponent? {
        difficulty.map { AIOpponent(difficulty: $0) }
    }
}

/// Difficulty maps directly to GameplayKit's minimax look-ahead depth (plies).
enum ChessDifficulty: String, CaseIterable, Identifiable {
    case easy, medium, hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easy: return "Gentle"
        case .medium: return "Measured"
        case .hard: return "Sharp"
        }
    }

    var subtitle: String {
        switch self {
        case .easy: return "Looks one move ahead"
        case .medium: return "Looks two moves ahead"
        case .hard: return "Looks three moves ahead"
        }
    }

    /// Plies the strategist searches. Kept modest — depth grows the search
    /// tree fast in pure Swift, so we cap at 3 and run off the main thread.
    var lookAheadDepth: Int {
        switch self {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }

    /// Range (seconds) for the deliberate "thinking" pause before replying, so
    /// moves feel considered rather than instant.
    var thinkPause: ClosedRange<Double> {
        switch self {
        case .easy: return 0.5...1.0
        case .medium: return 0.8...1.6
        case .hard: return 1.0...2.0
        }
    }
}
