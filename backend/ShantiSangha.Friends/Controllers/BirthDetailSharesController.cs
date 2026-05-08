using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Controllers;

[ApiController]
[Authorize]
[Route("api/friends/birth-details-share")]
public class BirthDetailSharesController(
    IBirthDetailShareService service,
    ICurrentUser currentUser,
    ILogger<BirthDetailSharesController> logger) : ControllerBase
{
    /// <summary>
    /// Returns both directions for the current user: who they've shared with,
    /// and who has shared with them. iOS uses both lists to drive the toggle
    /// state and the "[Name] through your chart" affordance per friend.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetMyShares(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var grantedTo = await service.ListGrantedToAsync(user.Id, ct);
        var receivedFrom = await service.ListReceivedFromAsync(user.Id, ct);

        return Ok(new
        {
            grantedTo,    // userIds I've shared my chart with
            receivedFrom, // userIds who've shared their chart with me
        });
    }

    /// <summary>
    /// Grants the specified grantee access to the current user's birth chart.
    /// Idempotent — re-granting an existing share returns 200 with action="unchanged".
    /// </summary>
    [HttpPut("{granteeUserId:guid}")]
    public async Task<IActionResult> Grant(Guid granteeUserId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var created = await service.GrantAsync(user.Id, granteeUserId, ct);
            logger.LogInformation("birth_details_share.grant grantor={Grantor} grantee={Grantee} created={Created}",
                user.Id, granteeUserId, created);
            return Ok(new { action = created ? "granted" : "unchanged" });
        }
        catch (InvalidOperationException ex) when (ex.Message == "not friends")
        {
            return Forbid();
        }
        catch (InvalidOperationException ex)
        {
            return UnprocessableEntity(new { error = ex.Message });
        }
    }

    /// <summary>
    /// Revokes a previously granted share. The grantee's pair reading and
    /// chat about this user become inaccessible immediately (the pair-reading
    /// endpoint will refuse, and on next view the cached row is removed).
    /// </summary>
    [HttpDelete("{granteeUserId:guid}")]
    public async Task<IActionResult> Revoke(Guid granteeUserId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var removed = await service.RevokeAsync(user.Id, granteeUserId, ct);
        logger.LogInformation("birth_details_share.revoke grantor={Grantor} grantee={Grantee} removed={Removed}",
            user.Id, granteeUserId, removed);
        return NoContent();
    }
}
