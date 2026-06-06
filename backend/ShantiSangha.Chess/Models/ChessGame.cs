namespace ShantiSangha.Chess.Models;

public enum ChessGameStatus
{
    Active,
    WhiteWon,
    BlackWon,
    Draw
}

/// One friend-vs-friend game, keyed to a friendship (the realtime channel).
/// Compact v1 stores only the latest position (FEN) + last move — no per-move
/// history table. The client is trusted for legality; the server validates only
/// turn ownership.
public class ChessGame
{
    public Guid Id { get; set; }
    public Guid FriendshipId { get; set; }
    public Guid WhiteUserId { get; set; }
    public Guid BlackUserId { get; set; }
    /// Current position in FEN. Standard start position on creation.
    public string Fen { get; set; } = "";
    /// Last move in UCI long algebraic (e.g. "e2e4", "e7e8q") — drives animation.
    public string? LastMoveUci { get; set; }
    /// Plies played; even = white to move, odd = black to move.
    public int MoveCount { get; set; }
    public ChessGameStatus Status { get; set; }
    public Guid? WinnerUserId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}
