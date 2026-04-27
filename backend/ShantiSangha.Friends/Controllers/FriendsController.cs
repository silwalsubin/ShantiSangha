using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Controllers;

[ApiController]
[Authorize]
[Route("api/friends")]
public class FriendsController(
    IFriendsService service,
    ICurrentUser currentUser,
    IConfiguration config,
    ILogger<FriendsController> logger) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> ListFriends(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.ListFriendsAsync(user.Id, ct);
        return Ok(result);
    }

    [HttpGet("{friendshipId:guid}")]
    public async Task<IActionResult> GetFriend(Guid friendshipId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.GetFriendAsync(user.Id, friendshipId, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPost("invitations")]
    public async Task<IActionResult> CreateInvitation(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.CreateInvitationAsync(user.Id, GetInviteBaseUrl(), ct);
            logger.LogInformation("friends.invite.created user={UserId} invite={InviteId}",
                user.Id, result.InvitationId);
            return Created($"/api/friends/invitations/{result.InvitationId}", result);
        }
        catch (FriendsServiceException ex) when (ex.Code == "display_name_required")
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
        catch (FriendsServiceException ex) when (ex.Code is "too_many_active_invites" or "rate_limited")
        {
            return StatusCode(Microsoft.AspNetCore.Http.StatusCodes.Status429TooManyRequests,
                new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpGet("invitations")]
    public async Task<IActionResult> ListInvitations(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.ListInvitationsAsync(user.Id, GetInviteBaseUrl(), ct);
        return Ok(result);
    }

    [HttpDelete("invitations/{invitationId:guid}")]
    public async Task<IActionResult> RevokeInvitation(Guid invitationId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var ok = await service.RevokeInvitationAsync(user.Id, invitationId, ct);
        return ok ? NoContent() : NotFound();
    }

    [HttpGet("invitations/preview/{token}")]
    public async Task<IActionResult> PreviewInvitation(string token, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.PreviewInvitationAsync(user.Id, token, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPost("invitations/accept")]
    public async Task<IActionResult> AcceptInvitation(
        [FromBody] AcceptInvitationRequest body, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        if (string.IsNullOrWhiteSpace(body.Token))
            return BadRequest(new { error = "missing_token" });

        try
        {
            var result = await service.AcceptInvitationAsync(user.Id, body.Token, ct);
            logger.LogInformation("friends.invite.accepted user={UserId} friendship={FriendshipId}",
                user.Id, result.FriendshipId);
            return Ok(result);
        }
        catch (FriendsServiceException ex)
        {
            var status = ex.Code switch
            {
                "self" => Microsoft.AspNetCore.Http.StatusCodes.Status422UnprocessableEntity,
                "already_friends" => Microsoft.AspNetCore.Http.StatusCodes.Status409Conflict,
                "expired" or "revoked" or "already_used" => Microsoft.AspNetCore.Http.StatusCodes.Status410Gone,
                _ => Microsoft.AspNetCore.Http.StatusCodes.Status400BadRequest
            };
            return StatusCode(status, new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpDelete("{friendshipId:guid}")]
    public async Task<IActionResult> EndFriendship(Guid friendshipId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var ok = await service.EndFriendshipAsync(user.Id, friendshipId, ct);
        if (ok)
            logger.LogInformation("friends.ended user={UserId} friendship={FriendshipId}", user.Id, friendshipId);
        return ok ? NoContent() : NotFound();
    }

    [HttpPatch("{friendshipId:guid}")]
    public async Task<IActionResult> UpdateAnnotations(
        Guid friendshipId,
        [FromBody] UpdateFriendAnnotationsRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.UpdateFriendAnnotationsAsync(user.Id, friendshipId, body, ct);
        return result is null ? NotFound() : Ok(result);
    }

    private string GetInviteBaseUrl() =>
        config["FRIENDS_INVITE_BASE_URL"]
            ?? Environment.GetEnvironmentVariable("FRIENDS_INVITE_BASE_URL")
            ?? "https://shantisangha.com";
}
