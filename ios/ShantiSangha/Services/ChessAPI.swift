import Foundation

/// Server representation of a friend game (matches the backend
/// `ChessGameResponse`). The board is reconstructed from `fen`.
struct ChessGameDTO: Codable {
    let id: UUID
    let friendshipId: UUID
    let whiteUserId: UUID
    let blackUserId: UUID
    let fen: String
    let lastMoveUci: String?
    let moveCount: Int
    let status: String          // "Active" | "WhiteWon" | "BlackWon" | "Draw"
    let winnerUserId: UUID?
}

/// REST wrapper for friend-vs-friend chess (compact v1). Moves are trusted by
/// the server (turn-ownership checks only); legality is enforced client-side.
enum ChessAPI {
    private struct CreateBody: Encodable { let friendshipId: UUID; let opponentUserId: UUID }
    private struct MoveBody: Encodable { let fen: String; let uci: String; let result: String? }

    /// Create — or return the existing active — game for a friendship.
    static func createOrGet(friendshipId: UUID, opponentUserId: UUID) async throws -> ChessGameDTO {
        try await ApiService.shared.post("/chess/games",
            body: CreateBody(friendshipId: friendshipId, opponentUserId: opponentUserId))
    }

    /// The active game for a friendship (throws if none — 404).
    static func active(friendshipId: UUID) async throws -> ChessGameDTO {
        try await ApiService.shared.get("/chess/games/\(friendshipId.uuidString.lowercased())")
    }

    /// Submit a move. `result` is "checkmate" | "stalemate" | "draw" | nil.
    static func move(friendshipId: UUID, fen: String, uci: String, result: String?) async throws -> ChessGameDTO {
        try await ApiService.shared.post("/chess/games/\(friendshipId.uuidString.lowercased())/moves",
            body: MoveBody(fen: fen, uci: uci, result: result))
    }

    @discardableResult
    static func resign(friendshipId: UUID) async throws -> ChessGameDTO {
        try await ApiService.shared.post("/chess/games/\(friendshipId.uuidString.lowercased())/resign")
    }
}
