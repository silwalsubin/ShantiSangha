using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
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

        var result = await goalService.CreateAsync(user.Id, body, ct);
        return ToActionResult(result);
    }

    [HttpGet]
    public async Task<IActionResult> List(string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.ListAsync(user.Id, date, ct);
        return ToActionResult(result);
    }

    [HttpGet("today")]
    public async Task<IActionResult> GetToday(string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetTodayAsync(user.Id, date, ct);
        return ToActionResult(result);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetByIdAsync(id, user.Id, date, ct);
        return ToActionResult(result);
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(
        Guid id, [FromBody] UpdateGoalRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.UpdateAsync(id, user.Id, body, ct);
        return ToActionResult(result);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.DeleteAsync(id, user.Id, ct);
        return ToActionResult(result);
    }

    [HttpPost("{id:guid}/checkin")]
    public async Task<IActionResult> CheckIn(
        Guid id, [FromBody] CheckInRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.CheckInAsync(id, user.Id, body, ct);
        return ToActionResult(result);
    }

    [HttpDelete("{id:guid}/checkin")]
    public async Task<IActionResult> UndoCheckIn(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.UndoCheckInAsync(id, user.Id, date, ct);
        return ToActionResult(result);
    }

    [HttpGet("{id:guid}/checkins")]
    public async Task<IActionResult> GetCheckIns(
        Guid id, string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetCheckInsAsync(id, user.Id, from, to, ct);
        return ToActionResult(result);
    }

    [HttpPost("{id:guid}/reset")]
    public async Task<IActionResult> Reset(Guid id, string? date = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.ResetAsync(id, user.Id, date, ct);
        return ToActionResult(result);
    }

    [HttpGet("{id:guid}/history")]
    public async Task<IActionResult> GetHistory(
        Guid id, int page = 1, int pageSize = 50, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetHistoryAsync(id, user.Id, page, pageSize, ct);
        return ToActionResult(result);
    }

    [HttpGet("{id:guid}/nudge")]
    public async Task<IActionResult> GetNudge(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetNudgeAsync(id, user.Id, ct);
        return ToActionResult(result);
    }

    [HttpGet("journey")]
    public async Task<IActionResult> GetJourney(
        string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetJourneyAsync(user.Id, from, to, ct);
        return ToActionResult(result);
    }

    [HttpGet("journey/reflection")]
    public async Task<IActionResult> GetJourneyReflection(
        string? from = null, string? to = null, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await goalService.GetJourneyReflectionAsync(user.Id, from, to, ct);
        return ToActionResult(result);
    }

    private static IActionResult ToActionResult(IResult result)
    {
        return new HttpResultActionResult(result);
    }

    private sealed class HttpResultActionResult(IResult result) : IActionResult
    {
        public Task ExecuteResultAsync(ActionContext context)
        {
            return result.ExecuteAsync(context.HttpContext);
        }
    }
}
