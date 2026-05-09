using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Controllers;

/// Per-connection keepsakes — photos, videos, files. Two-step upload
/// (presigned PUT, then commit) keeps bytes off ECS. List returns
/// fresh presigned download URLs each time.
[ApiController]
[Authorize]
[Route("api/connections/{connectionId:guid}/attachments")]
public class ConnectionAttachmentsController(
    IConnectionAttachmentsService service,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(Guid connectionId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var rows = await service.ListAsync(user.Id, connectionId, ct);
        return rows is null ? NotFound() : Ok(rows);
    }

    [HttpPost("upload-url")]
    public async Task<IActionResult> CreateUploadUrl(
        Guid connectionId,
        [FromBody] CreateConnectionAttachmentUploadRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var resp = await service.CreateUploadUrlAsync(user.Id, connectionId, body, ct);
            return resp is null ? NotFound() : Ok(resp);
        }
        catch (FriendsServiceException ex)
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPost]
    public async Task<IActionResult> Commit(
        Guid connectionId,
        [FromBody] CommitConnectionAttachmentRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var resp = await service.CommitAsync(user.Id, connectionId, body, ct);
            return resp is null ? NotFound() : Ok(resp);
        }
        catch (FriendsServiceException ex) when (ex.Code == "forbidden")
        {
            return Forbid();
        }
        catch (FriendsServiceException ex)
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPatch("{attachmentId:guid}")]
    public async Task<IActionResult> Update(
        Guid connectionId,
        Guid attachmentId,
        [FromBody] UpdateConnectionAttachmentRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var resp = await service.UpdateAsync(user.Id, connectionId, attachmentId, body, ct);
            return resp is null ? NotFound() : Ok(resp);
        }
        catch (FriendsServiceException ex)
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpDelete("{attachmentId:guid}")]
    public async Task<IActionResult> Delete(
        Guid connectionId,
        Guid attachmentId,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var ok = await service.DeleteAsync(user.Id, connectionId, attachmentId, ct);
        return ok ? NoContent() : NotFound();
    }
}
