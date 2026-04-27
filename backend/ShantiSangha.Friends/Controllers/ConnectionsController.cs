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
}
