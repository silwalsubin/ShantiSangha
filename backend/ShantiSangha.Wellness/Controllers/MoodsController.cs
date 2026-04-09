using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Contracts;
using ShantiSangha.Wellness.Services;

namespace ShantiSangha.Wellness.Controllers;

[ApiController]
[Authorize]
[Route("api/moods")]
public class MoodsController(IMoodService moodService, ICurrentUser currentUser) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> CreateCheckin([FromBody] CreateMoodCheckinRequest request, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        if (request.Score is < 1 or > 10)
            return BadRequest("Score must be between 1 and 10.");

        var result = await moodService.CreateCheckinAsync(user.Id, request, ct);
        return Created($"/moods/{result.Id}", result);
    }

    [HttpGet]
    public async Task<IActionResult> ListCheckins(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 30,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await moodService.ListCheckinsAsync(user.Id, from, to, page, pageSize, ct);
        return Ok(result);
    }

    [HttpGet("trends")]
    public async Task<IActionResult> GetTrends(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await moodService.GetTrendsAsync(user.Id, from, to, ct);
        return Ok(result);
    }
}
