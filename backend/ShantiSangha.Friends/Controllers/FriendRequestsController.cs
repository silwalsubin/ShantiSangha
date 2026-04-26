using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Controllers;

[ApiController]
[Authorize]
[Route("api/friends/requests")]
public class FriendRequestsController(
    IFriendRequestsService service,
    ICurrentUser currentUser,
    ILogger<FriendRequestsController> logger) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Send(
        [FromBody] SendFriendRequestRequest body, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        if (body.ToUserId == Guid.Empty)
            return BadRequest(new { error = "missing_to_user_id" });

        try
        {
            var result = await service.SendAsync(user.Id, body.ToUserId, ct);
            logger.LogInformation("friends.request.sent from={FromUserId} to={ToUserId} request={RequestId}",
                user.Id, body.ToUserId, result.Id);
            return Created($"/api/friends/requests/{result.Id}", result);
        }
        catch (FriendsServiceException ex)
        {
            var status = ex.Code switch
            {
                "self" => Microsoft.AspNetCore.Http.StatusCodes.Status422UnprocessableEntity,
                "user_not_found" => Microsoft.AspNetCore.Http.StatusCodes.Status404NotFound,
                "already_friends" or "already_pending" => Microsoft.AspNetCore.Http.StatusCodes.Status409Conflict,
                _ => Microsoft.AspNetCore.Http.StatusCodes.Status400BadRequest
            };
            return StatusCode(status, new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpGet("incoming")]
    public async Task<IActionResult> ListIncoming(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.ListIncomingAsync(user.Id, ct);
        return Ok(result);
    }

    [HttpGet("outgoing")]
    public async Task<IActionResult> ListOutgoing(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.ListOutgoingAsync(user.Id, ct);
        return Ok(result);
    }

    [HttpPost("{requestId:guid}/accept")]
    public async Task<IActionResult> Accept(Guid requestId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.AcceptAsync(user.Id, requestId, ct);
            logger.LogInformation("friends.request.accepted user={UserId} request={RequestId}", user.Id, requestId);
            return Ok(result);
        }
        catch (FriendsServiceException ex)
        {
            var status = ex.Code switch
            {
                "not_found" => Microsoft.AspNetCore.Http.StatusCodes.Status404NotFound,
                "forbidden" => Microsoft.AspNetCore.Http.StatusCodes.Status403Forbidden,
                "not_pending" => Microsoft.AspNetCore.Http.StatusCodes.Status410Gone,
                _ => Microsoft.AspNetCore.Http.StatusCodes.Status400BadRequest
            };
            return StatusCode(status, new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPost("{requestId:guid}/decline")]
    public async Task<IActionResult> Decline(Guid requestId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var ok = await service.DeclineAsync(user.Id, requestId, ct);
            return ok ? NoContent() : NotFound();
        }
        catch (FriendsServiceException ex)
        {
            return StatusCode(Microsoft.AspNetCore.Http.StatusCodes.Status403Forbidden,
                new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpDelete("{requestId:guid}")]
    public async Task<IActionResult> Cancel(Guid requestId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var ok = await service.CancelAsync(user.Id, requestId, ct);
            return ok ? NoContent() : NotFound();
        }
        catch (FriendsServiceException ex)
        {
            return StatusCode(Microsoft.AspNetCore.Http.StatusCodes.Status403Forbidden,
                new { error = ex.Code, message = ex.Message });
        }
    }
}
