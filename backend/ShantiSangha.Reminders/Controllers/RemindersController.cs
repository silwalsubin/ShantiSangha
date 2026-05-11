using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Reminders.Contracts;
using ShantiSangha.Reminders.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Reminders.Controllers;

[ApiController]
[Authorize]
[Route("api/reminders")]
public class RemindersController(IReminderService service, ICurrentUser currentUser) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateReminderRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await service.CreateAsync(user.Id, body, ct);
            return CreatedAtAction(nameof(GetById), new { id = result.Id }, result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet]
    public async Task<IActionResult> List(
        Guid? connectionId = null, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.ListAsync(user.Id, connectionId, date, ct);
        return Ok(result);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(
        Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await service.GetByIdAsync(id, user.Id, date, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(
        Guid id, [FromBody] UpdateReminderRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var found = await service.UpdateAsync(id, user.Id, body, ct);
            return found ? NoContent() : NotFound();
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var found = await service.DeleteAsync(id, user.Id, ct);
        return found ? NoContent() : NotFound();
    }
}
