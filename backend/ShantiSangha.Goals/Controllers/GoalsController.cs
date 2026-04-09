using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Goals.Contracts;
using ShantiSangha.Goals.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Goals.Controllers;

[ApiController]
[Authorize]
[Route("api/goals")]
public class GoalsController(IGoalService goalService, ICurrentUser currentUser) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateGoalRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await goalService.CreateAsync(user.Id, body, ct);
            return CreatedAtAction(nameof(GetById), new { id = result.Id }, result);
        }
        catch (DbUpdateException)
        {
            return Conflict(new { error = "A goal with that title already exists." });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet]
    public async Task<IActionResult> List(string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.ListAsync(user.Id, date, ct);
        return Ok(result);
    }

    [HttpGet("today")]
    public async Task<IActionResult> GetToday(string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetTodayAsync(user.Id, date, ct);
        return Ok(result);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetByIdAsync(id, user.Id, date, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(
        Guid id, [FromBody] UpdateGoalRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var found = await goalService.UpdateAsync(id, user.Id, body, ct);
            return found ? NoContent() : NotFound();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { error = "A goal with that title already exists." });
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

        var found = await goalService.DeleteAsync(id, user.Id, ct);
        return found ? NoContent() : NotFound();
    }

    [HttpPost("{id:guid}/checkin")]
    public async Task<IActionResult> CheckIn(
        Guid id, [FromBody] CheckInRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.CheckInAsync(id, user.Id, body, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpDelete("{id:guid}/checkin")]
    public async Task<IActionResult> UndoCheckIn(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var found = await goalService.UndoCheckInAsync(id, user.Id, date, ct);
        return found ? NoContent() : NotFound();
    }

    [HttpGet("{id:guid}/checkins")]
    public async Task<IActionResult> GetCheckIns(
        Guid id, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetCheckInsAsync(id, user.Id, from, to, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPost("{id:guid}/reset")]
    public async Task<IActionResult> Reset(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var found = await goalService.ResetAsync(id, user.Id, date, ct);
            return found ? NoContent() : NotFound();
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("{id:guid}/history")]
    public async Task<IActionResult> GetHistory(
        Guid id, int page = 1, int pageSize = 50, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetHistoryAsync(id, user.Id, page, pageSize, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpGet("{id:guid}/nudge")]
    public async Task<IActionResult> GetNudge(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetNudgeAsync(id, user.Id, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpGet("journey")]
    public async Task<IActionResult> GetJourney(
        string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetJourneyAsync(user.Id, from, to, ct);
        return Ok(result);
    }

    [HttpGet("journey/reflection")]
    public async Task<IActionResult> GetJourneyReflection(
        string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetJourneyReflectionAsync(user.Id, from, to, ct);
        return Ok(result);
    }
}
