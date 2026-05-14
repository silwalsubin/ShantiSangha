using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Friends.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Controllers;

[ApiController]
[Authorize]
[Route("api/friend-messages")]
public class FriendMessageSuggestionsController(
    IFriendMessageSuggestionService suggestions,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpPost("{messageId:guid}/suggestion/dismiss")]
    public async Task<IActionResult> Dismiss(Guid messageId, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var ok = await suggestions.DismissAsync(user.Id, messageId, ct);
        return ok ? NoContent() : NotFound();
    }

    public record AcceptSuggestionRequest(Guid ReminderId);

    [HttpPost("{messageId:guid}/suggestion/accept")]
    public async Task<IActionResult> Accept(
        Guid messageId,
        [FromBody] AcceptSuggestionRequest body,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        if (body.ReminderId == Guid.Empty)
            return BadRequest(new { error = "reminderId is required" });

        var ok = await suggestions.AcceptAsync(user.Id, messageId, body.ReminderId, ct);
        return ok ? NoContent() : NotFound();
    }
}
