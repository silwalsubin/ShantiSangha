using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Chess.Contracts;
using ShantiSangha.Chess.Data;
using ShantiSangha.Chess.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Chess.Services;

/// Friend-game lifecycle. Compact v1: the client is trusted for legality; the
/// server validates only turn ownership, persists the latest FEN, broadcasts
/// over the chat WebSocket (channel = friendship id), and pushes the opponent.
public class ChessGameService(
    ChessDbContext db,
    IRealtimeBroadcaster realtime,
    IPushNotificationService push,
    ILogger<ChessGameService> logger) : IChessGameService
{
    private const string StartFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

    public async Task<ChessGameResponse> CreateOrGetActiveAsync(Guid callerId, Guid friendshipId, Guid opponentId, CancellationToken ct)
    {
        var existing = await ActiveGameAsync(friendshipId, ct);
        if (existing is not null)
        {
            EnsureParticipant(existing, callerId);
            return Map(existing);
        }

        // Deterministic colors so both clients agree without coordinating:
        // the smaller user id plays white.
        var (white, black) = callerId.CompareTo(opponentId) < 0
            ? (callerId, opponentId)
            : (opponentId, callerId);

        var game = new ChessGame
        {
            Id = Guid.NewGuid(),
            FriendshipId = friendshipId,
            WhiteUserId = white,
            BlackUserId = black,
            Fen = StartFen,
            MoveCount = 0,
            Status = ChessGameStatus.Active,
            CreatedAt = DateTime.UtcNow
        };
        db.Games.Add(game);
        await db.SaveChangesAsync(ct);

        await BroadcastAsync(friendshipId, "chess_game_created", Map(game), ct);
        return Map(game);
    }

    public async Task<ChessGameResponse?> GetActiveAsync(Guid callerId, Guid friendshipId, CancellationToken ct)
    {
        var game = await ActiveGameAsync(friendshipId, ct);
        if (game is null) return null;
        if (game.WhiteUserId != callerId && game.BlackUserId != callerId) return null;
        return Map(game);
    }

    public async Task<ChessGameResponse> SubmitMoveAsync(Guid callerId, Guid friendshipId, MakeMoveRequest move, CancellationToken ct)
    {
        var game = await ActiveGameAsync(friendshipId, ct)
            ?? throw new ChessServiceException("no_active_game", "No active game for this friendship.");
        EnsureParticipant(game, callerId);

        var whiteToMove = game.MoveCount % 2 == 0;
        var sideToMove = whiteToMove ? game.WhiteUserId : game.BlackUserId;
        if (callerId != sideToMove)
            throw new ChessServiceException("not_your_turn", "It is not your turn.");

        game.Fen = move.Fen;
        game.LastMoveUci = move.Uci;
        game.MoveCount += 1;
        game.UpdatedAt = DateTime.UtcNow;
        ApplyResult(game, move.Result, moverId: callerId);
        await db.SaveChangesAsync(ct);

        var dto = Map(game);
        var kind = game.Status == ChessGameStatus.Active ? "chess_move" : "chess_game_over";
        await BroadcastAsync(friendshipId, kind, dto, ct);

        var opponentId = callerId == game.WhiteUserId ? game.BlackUserId : game.WhiteUserId;
        await NotifyAsync(opponentId, friendshipId, game.Status, ct);
        return dto;
    }

    public async Task<ChessGameResponse> ResignAsync(Guid callerId, Guid friendshipId, CancellationToken ct)
    {
        var game = await ActiveGameAsync(friendshipId, ct)
            ?? throw new ChessServiceException("no_active_game", "No active game for this friendship.");
        EnsureParticipant(game, callerId);

        var winner = callerId == game.WhiteUserId ? game.BlackUserId : game.WhiteUserId;
        game.Status = winner == game.WhiteUserId ? ChessGameStatus.WhiteWon : ChessGameStatus.BlackWon;
        game.WinnerUserId = winner;
        game.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        var dto = Map(game);
        await BroadcastAsync(friendshipId, "chess_game_over", dto, ct);
        await NotifyAsync(winner, friendshipId, game.Status, ct);
        return dto;
    }

    // MARK: helpers

    private Task<ChessGame?> ActiveGameAsync(Guid friendshipId, CancellationToken ct) =>
        db.Games.FirstOrDefaultAsync(g => g.FriendshipId == friendshipId && g.Status == ChessGameStatus.Active, ct);

    private static void EnsureParticipant(ChessGame g, Guid userId)
    {
        if (g.WhiteUserId != userId && g.BlackUserId != userId)
            throw new ChessServiceException("not_participant", "You are not a player in this game.");
    }

    private static void ApplyResult(ChessGame g, string? result, Guid moverId)
    {
        switch (result)
        {
            case "checkmate":
                // The side that just moved delivered mate.
                g.Status = moverId == g.WhiteUserId ? ChessGameStatus.WhiteWon : ChessGameStatus.BlackWon;
                g.WinnerUserId = moverId;
                break;
            case "stalemate":
            case "draw":
                g.Status = ChessGameStatus.Draw;
                break;
            default:
                break; // game continues
        }
    }

    private async Task BroadcastAsync(Guid friendshipId, string kind, object payload, CancellationToken ct)
    {
        try { await realtime.PublishAsync(friendshipId, kind, payload, ct); }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Chess realtime broadcast of {Kind} failed for {FriendshipId}", kind, friendshipId);
        }
    }

    private async Task NotifyAsync(Guid recipientId, Guid friendshipId, ChessGameStatus status, CancellationToken ct)
    {
        var body = status == ChessGameStatus.Active ? "Your move" : "The game is over";
        try
        {
            await push.SendAlertPushAsync(recipientId,
                title: "Chess",
                body: body,
                data: new Dictionary<string, string>
                {
                    ["type"] = "chess_move",
                    ["friendshipId"] = friendshipId.ToString()
                }, ct: ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Chess push to {RecipientId} failed", recipientId);
        }
    }

    private static ChessGameResponse Map(ChessGame g) => new(
        g.Id, g.FriendshipId, g.WhiteUserId, g.BlackUserId,
        g.Fen, g.LastMoveUci, g.MoveCount, g.Status.ToString(), g.WinnerUserId);
}
