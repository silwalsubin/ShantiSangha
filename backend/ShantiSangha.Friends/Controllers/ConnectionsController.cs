using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Controllers;

[ApiController]
[Authorize]
[Route("api/connections")]
public class ConnectionsController(
    IConnectionsService service,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var rows = await service.ListAsync(user.Id, ct);
        return Ok(rows);
    }

    [HttpGet("{connectionId:guid}")]
    public async Task<IActionResult> Get(Guid connectionId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        var row = await service.GetAsync(user.Id, connectionId, ct);
        return row is null ? NotFound() : Ok(row);
    }

    [HttpPost]
    public async Task<IActionResult> CreateLocal(
        [FromBody] CreateConnectionRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var created = await service.CreateLocalAsync(user.Id, body, ct);
            return CreatedAtAction(nameof(Get), new { connectionId = created.Id }, created);
        }
        catch (FriendsServiceException ex)
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPatch("{connectionId:guid}")]
    public async Task<IActionResult> Update(
        Guid connectionId,
        [FromBody] UpdateConnectionRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var updated = await service.UpdateAsync(user.Id, connectionId, body, ct);
            return updated is null ? NotFound() : Ok(updated);
        }
        catch (FriendsServiceException ex)
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPatch("{connectionId:guid}/person")]
    public async Task<IActionResult> UpdatePerson(
        Guid connectionId,
        [FromBody] UpdatePersonRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var updated = await service.UpdatePersonAsync(user.Id, connectionId, body, ct);
            return updated is null ? NotFound() : Ok(updated);
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

    [HttpDelete("{connectionId:guid}")]
    public async Task<IActionResult> Delete(Guid connectionId, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var ok = await service.DeleteAsync(user.Id, connectionId, ct);
        return ok ? NoContent() : NotFound();
    }

    // ── Important dates ─────────────────────────────────────────────
    // Owner-private list (birthday, anniversary, day-we-met). The list
    // already ships embedded in `ConnectionResponse.Dates`; these
    // endpoints just mutate it.

    [HttpPost("{connectionId:guid}/dates")]
    public async Task<IActionResult> AddDate(
        Guid connectionId,
        [FromBody] AddConnectionDateRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var created = await service.AddDateAsync(user.Id, connectionId, body, ct);
            return created is null ? NotFound() : Ok(created);
        }
        catch (FriendsServiceException ex)
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpPut("{connectionId:guid}/dates/{dateId:guid}")]
    public async Task<IActionResult> UpdateDate(
        Guid connectionId,
        Guid dateId,
        [FromBody] UpdateConnectionDateRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var updated = await service.UpdateDateAsync(user.Id, connectionId, dateId, body, ct);
            return updated is null ? NotFound() : Ok(updated);
        }
        catch (FriendsServiceException ex)
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
    }

    [HttpDelete("{connectionId:guid}/dates/{dateId:guid}")]
    public async Task<IActionResult> DeleteDate(
        Guid connectionId,
        Guid dateId,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var ok = await service.DeleteDateAsync(user.Id, connectionId, dateId, ct);
        return ok ? NoContent() : NotFound();
    }

    // ── Owner-private avatar ────────────────────────────────────────
    // Step 1 of the avatar upload — hand back a presigned PUT URL the
    // client uses to ship JPEG bytes directly to S3. Step 2 is the
    // existing `PATCH /api/connections/{id}` with `PrivateAvatarKey`.
    // Removal also goes through PATCH with `ClearPrivateAvatar = true`.

    [HttpPost("{connectionId:guid}/avatar/upload-url")]
    public async Task<IActionResult> CreateAvatarUploadUrl(
        Guid connectionId,
        [FromBody] CreateConnectionAvatarUploadRequest body,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.CreateAvatarUploadUrlAsync(user.Id, connectionId, body, ct);
            return result is null ? NotFound() : Ok(result);
        }
        catch (FriendsServiceException ex)
        {
            return UnprocessableEntity(new { error = ex.Code, message = ex.Message });
        }
    }
}
