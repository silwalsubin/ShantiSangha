using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Practices.Contracts;
using ShantiSangha.Practices.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Practices.Controllers;

[ApiController]
[Authorize]
[Route("api/practices")]
public class PracticesController(IPracticeService practiceService, ICurrentUser currentUser) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreatePracticeRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var result = await practiceService.CreateAsync(user.Id, body, ct);
            return CreatedAtAction(nameof(GetById), new { id = result.Id }, result);
        }
        catch (DbUpdateException)
        {
            return Conflict(new { error = "A practice with that title already exists." });
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

        var result = await practiceService.ListAsync(user.Id, date, ct);
        return Ok(result);
    }

    [HttpGet("today")]
    public async Task<IActionResult> GetToday(string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await practiceService.GetTodayAsync(user.Id, date, ct);
        return Ok(result);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await practiceService.GetByIdAsync(id, user.Id, date, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(
        Guid id, [FromBody] UpdatePracticeRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var found = await practiceService.UpdateAsync(id, user.Id, body, ct);
            return found ? NoContent() : NotFound();
        }
        catch (DbUpdateException)
        {
            return Conflict(new { error = "A practice with that title already exists." });
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

        var found = await practiceService.DeleteAsync(id, user.Id, ct);
        return found ? NoContent() : NotFound();
    }

    [HttpPost("{id:guid}/checkin")]
    public async Task<IActionResult> CheckIn(
        Guid id, [FromBody] CheckInRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await practiceService.CheckInAsync(id, user.Id, body, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpDelete("{id:guid}/checkin")]
    public async Task<IActionResult> UndoCheckIn(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var found = await practiceService.UndoCheckInAsync(id, user.Id, date, ct);
        return found ? NoContent() : NotFound();
    }

    [HttpGet("{id:guid}/checkins")]
    public async Task<IActionResult> GetCheckIns(
        Guid id, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await practiceService.GetCheckInsAsync(id, user.Id, from, to, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpPost("{id:guid}/reset")]
    public async Task<IActionResult> Reset(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        try
        {
            var found = await practiceService.ResetAsync(id, user.Id, date, ct);
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

        var result = await practiceService.GetHistoryAsync(id, user.Id, page, pageSize, ct);
        return result is null ? NotFound() : Ok(result);
    }

    [HttpGet("journey")]
    public async Task<IActionResult> GetJourney(
        string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await practiceService.GetJourneyAsync(user.Id, from, to, ct);
        return Ok(result);
    }

    [HttpGet("journey/reflection")]
    public async Task<IActionResult> GetJourneyReflection(
        string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await practiceService.GetJourneyReflectionAsync(user.Id, from, to, ct);
        return Ok(result);
    }
}
