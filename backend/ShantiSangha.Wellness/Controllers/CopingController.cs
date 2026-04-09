using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Contracts;
using ShantiSangha.Wellness.Services;

namespace ShantiSangha.Wellness.Controllers;

[ApiController]
[Authorize]
[Route("api/exercises")]
public class CopingController(ICopingService copingService, ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public IActionResult GetCatalog()
    {
        return Ok(copingService.GetExercises());
    }

    [HttpPost("{slug}/sessions")]
    public async Task<IActionResult> LogSession(string slug, [FromBody] LogSessionRequest request, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await copingService.LogSessionAsync(user.Id, slug, request, ct);
        if (result is null) return NotFound("Exercise not found.");

        return Created($"/exercises/sessions/{result.Id}", result);
    }

    [HttpGet("sessions")]
    public async Task<IActionResult> ListSessions(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await copingService.ListSessionsAsync(user.Id, page, pageSize, ct);
        return Ok(result);
    }
}
