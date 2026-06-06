using ShantiSangha.Chess.Contracts;

namespace ShantiSangha.Chess.Services;

public interface IChessGameService
{
    Task<ChessGameResponse> CreateOrGetActiveAsync(Guid callerId, Guid friendshipId, Guid opponentId, CancellationToken ct);
    Task<ChessGameResponse?> GetActiveAsync(Guid callerId, Guid friendshipId, CancellationToken ct);
    Task<ChessGameResponse> SubmitMoveAsync(Guid callerId, Guid friendshipId, MakeMoveRequest move, CancellationToken ct);
    Task<ChessGameResponse> ResignAsync(Guid callerId, Guid friendshipId, CancellationToken ct);
}
