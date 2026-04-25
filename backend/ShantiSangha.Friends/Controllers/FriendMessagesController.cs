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
            var result = await service.SendTextAsync(user.Id, friendshipId, body.Body, ct);
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
}

public record UploadUrlRequest(string ContentType);
