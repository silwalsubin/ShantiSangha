using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Chess.Contracts;
using ShantiSangha.Chess.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Chess.Controllers;

[ApiController]
[Authorize]
[Route("api/chess")]
public class ChessGamesController(
    IChessGameService service,
    ICurrentUser currentUser) : ControllerBase
{
    /// Create (or return the existing active) game for a friendship.
    [HttpPost("games")]
    public async Task<IActionResult> CreateGame([FromBody] CreateGameRequest body, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        try
        {
            var game = await service.CreateOrGetActiveAsync(user.Id, body.FriendshipId, body.OpponentUserId, ct);
            return Ok(game);
        }
        catch (ChessServiceException ex)
        {
            return BadRequest(new { error = ex.Code, message = ex.Message });
        }
    }

    /// The active game for a friendship, or 404 if none.
    [HttpGet("games/{friendshipId:guid}")]
    public async Task<IActionResult> GetActive(Guid friendshipId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var game = await service.GetActiveAsync(user.Id, friendshipId, ct);
        return game is null ? NotFound() : Ok(game);
    }

    [HttpPost("games/{friendshipId:guid}/moves")]
    public async Task<IActionResult> MakeMove(Guid friendshipId, [FromBody] MakeMoveRequest body, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        try
        {
            var game = await service.SubmitMoveAsync(user.Id, friendshipId, body, ct);
            return Ok(game);
        }
        catch (ChessServiceException ex)
        {
            return BadRequest(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPost("games/{friendshipId:guid}/resign")]
    public async Task<IActionResult> Resign(Guid friendshipId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        try
        {
            var game = await service.ResignAsync(user.Id, friendshipId, ct);
            return Ok(game);
        }
        catch (ChessServiceException ex)
        {
            return BadRequest(new { error = ex.Code, message = ex.Message });
        }
    }
}
