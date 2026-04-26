using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Notifications.Contracts;
using ShantiSangha.Notifications.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Notifications.Controllers;

[ApiController]
[Authorize]
[Route("api/notifications")]
public class NotificationsController(
    IInboxService inbox,
    ICurrentUser currentUser) : ControllerBase
{
    /// <summary>
    /// Inbox list. Returns the current unread count plus the most recent
    /// page of notifications (newest-first). The unread count is folded
    /// into the same response so the client doesn't need a second round
    /// trip to render the bell-icon badge.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 30,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await inbox.ListAsync(user.Id, page, pageSize, ct);
        return Ok(result);
    }

    /// <summary>
    /// Cheap unread-count endpoint for refreshing the bell-icon badge
    /// without re-loading the full inbox. Used by the iOS layer on app
    /// foreground / silent push receipt.
    /// </summary>
    [HttpGet("unread-count")]
    public async Task<IActionResult> UnreadCount(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var count = await inbox.GetUnreadCountAsync(user.Id, ct);
        return Ok(new UnreadCountResponse(count));
    }

    /// <summary>
    /// Mark every unread notification for this user as viewed (bell badge
    /// clears). Idempotent — if there's nothing unread, returns 204 with
    /// updated=0. The iOS layer fires this when the user opens the inbox.
    /// </summary>
    [HttpPost("mark-viewed")]
    public async Task<IActionResult> MarkAllViewed(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var updated = await inbox.MarkAllViewedAsync(user.Id, ct);
        return Ok(new { updated });
    }
}
