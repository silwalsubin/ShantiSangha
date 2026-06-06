namespace ShantiSangha.Chess.Contracts;

/// Create (or fetch the existing active) game for a friendship. The client
/// supplies the opponent's user id; white is assigned deterministically (the
/// smaller user id) so both clients agree without a round-trip.
public record CreateGameRequest(Guid FriendshipId, Guid OpponentUserId);

/// A move, trusted from the client (compact v1). `Fen` is the new position,
/// `Uci` the move just played (for animation), `Result` one of
/// "checkmate" | "stalemate" | "draw" | null (game continues).
public record MakeMoveRequest(string Fen, string Uci, string? Result);

public record ChessGameResponse(
    Guid Id,
    Guid FriendshipId,
    Guid WhiteUserId,
    Guid BlackUserId,
    string Fen,
    string? LastMoveUci,
    int MoveCount,
    string Status,
    Guid? WinnerUserId);

/// Thrown by the service for expected, user-facing failures; the controller
/// maps it to a 400 with { error, message }.
public sealed class ChessServiceException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
