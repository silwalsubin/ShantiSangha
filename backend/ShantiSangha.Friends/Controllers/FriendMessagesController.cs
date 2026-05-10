using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Controllers;

[ApiController]
[Authorize]
[Route("api/friends/{friendshipId:guid}/messages")]
public class FriendMessagesController(
    IFriendMessagesService service,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(
        Guid friendshipId,
        [FromQuery] DateTime? before = null,
        [FromQuery] int limit = 50,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.ListMessagesAsync(user.Id, friendshipId, before, limit, ct);
        return result is null ? NotFound() : Ok(result);
    }

    /// Image + voice messages only, newest first. Backs the per-Connection
    /// "Chat Media & Files" archive without paging through walls of text.
    [HttpGet("media")]
    public async Task<IActionResult> ListMedia(
        Guid friendshipId,
        [FromQuery] DateTime? before = null,
        [FromQuery] int limit = 100,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.ListMediaMessagesAsync(user.Id, friendshipId, before, limit, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPost]
    public async Task<IActionResult> SendText(
        Guid friendshipId,
        [FromBody] SendTextMessageRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.SendTextAsync(user.Id, friendshipId, body.Body, body.ReplyToMessageId, ct);
            return result is null ? NotFound() : Created($"/api/friends/{friendshipId}/messages/{result.Id}", result);
        }
        catch (FriendsServiceException ex)
        {
            return BadRequest(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPost("image/upload-url")]
    public async Task<IActionResult> CreateImageUpload(
        Guid friendshipId,
        [FromBody] UploadUrlRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.CreateImageUploadAsync(user.Id, friendshipId, body.ContentType, ct);
            return result is null ? NotFound() : Ok(result);
        }
        catch (FriendsServiceException ex)
        {
            return BadRequest(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPost("image")]
    public async Task<IActionResult> CommitImage(
        Guid friendshipId,
        [FromBody] CommitMediaMessageRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.CommitImageMessageAsync(user.Id, friendshipId, body, ct);
            return result is null ? NotFound() : Created($"/api/friends/{friendshipId}/messages/{result.Id}", result);
        }
        catch (FriendsServiceException ex)
        {
            return BadRequest(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPost("voice/upload-url")]
    public async Task<IActionResult> CreateVoiceUpload(
        Guid friendshipId,
        [FromBody] UploadUrlRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.CreateVoiceUploadAsync(user.Id, friendshipId, body.ContentType, ct);
            return result is null ? NotFound() : Ok(result);
        }
        catch (FriendsServiceException ex)
        {
            return BadRequest(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPost("voice")]
    public async Task<IActionResult> CommitVoice(
        Guid friendshipId,
        [FromBody] CommitMediaMessageRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.CommitVoiceMessageAsync(user.Id, friendshipId, body, ct);
            return result is null ? NotFound() : Created($"/api/friends/{friendshipId}/messages/{result.Id}", result);
        }
        catch (FriendsServiceException ex)
        {
            return BadRequest(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPost("{messageId:guid}/read")]
    public async Task<IActionResult> MarkRead(
        Guid friendshipId, Guid messageId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var ok = await service.MarkReadAsync(user.Id, friendshipId, messageId, ct);
        return ok ? NoContent() : NotFound();
    }

    [HttpPost("read-through")]
    public async Task<IActionResult> MarkReadThrough(
        Guid friendshipId,
        [FromBody] MarkMessagesReadRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var ok = await service.MarkReadThroughAsync(user.Id, friendshipId, body.LastMessageId, ct);
        return ok ? NoContent() : NotFound();
    }

    [HttpPut("{messageId:guid}")]
    public async Task<IActionResult> EditText(
        Guid friendshipId,
        Guid messageId,
        [FromBody] EditTextMessageRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.EditTextAsync(user.Id, friendshipId, messageId, body.Body, ct);
            return result is null ? NotFound() : Ok(result);
        }
        catch (FriendsServiceException ex)
        {
            // 422 for the time-window case so the client can render a
            // friendly "edit window expired" message; other policy errors
            // (forbidden, wrong_kind, already_deleted) also surface here
            // with their machine-readable code.
            return ex.Code switch
            {
                "not_found"            => NotFound(new { error = ex.Code, message = ex.Message }),
                "forbidden"            => StatusCode(403, new { error = ex.Code, message = ex.Message }),
                "edit_window_expired"  => UnprocessableEntity(new { error = ex.Code, message = ex.Message }),
                _                      => BadRequest(new { error = ex.Code, message = ex.Message }),
            };
        }
    }

    [HttpPost("{messageId:guid}/reactions")]
    public async Task<IActionResult> React(
        Guid friendshipId,
        Guid messageId,
        [FromBody] AddReactionRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.ReactAsync(user.Id, friendshipId, messageId, body.Emoji, ct);
            return result is null ? NotFound() : Ok(result);
        }
        catch (FriendsServiceException ex)
        {
            return ex.Code switch
            {
                "not_found"        => NotFound(new { error = ex.Code, message = ex.Message }),
                "already_deleted"  => UnprocessableEntity(new { error = ex.Code, message = ex.Message }),
                _                  => BadRequest(new { error = ex.Code, message = ex.Message }),
            };
        }
    }

    [HttpDelete("{messageId:guid}/reactions")]
    public async Task<IActionResult> Unreact(
        Guid friendshipId,
        Guid messageId,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.UnreactAsync(user.Id, friendshipId, messageId, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpDelete("{messageId:guid}")]
    public async Task<IActionResult> Delete(
        Guid friendshipId,
        Guid messageId,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.DeleteAsync(user.Id, friendshipId, messageId, ct);
            return result is null ? NotFound() : Ok(result);
        }
        catch (FriendsServiceException ex)
        {
            return ex.Code switch
            {
                "not_found" => NotFound(new { error = ex.Code, message = ex.Message }),
                "forbidden" => StatusCode(403, new { error = ex.Code, message = ex.Message }),
                _           => BadRequest(new { error = ex.Code, message = ex.Message }),
            };
        }
    }
}

public record UploadUrlRequest(string ContentType);
