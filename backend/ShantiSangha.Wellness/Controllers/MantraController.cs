using Hangfire;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Jobs;

namespace ShantiSangha.Wellness.Controllers;

[ApiController]
[Authorize]
[Route("api/mantra")]
public class MantraController(
    WellnessDbContext db,
    ICurrentUser currentUser,
    IBackgroundJobClient jobs,
    ILogger<MantraController> logger) : ControllerBase
{
    [HttpGet("today")]
    public async Task<IActionResult> GetToday([FromQuery] string? date, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var mantra = await db.DailyMantras
            .Where(m => m.UserId == user.Id && m.Date == today)
            .Select(m => new { m.Content, m.Date })
            .FirstOrDefaultAsync(ct);

        if (mantra is not null)
        {
            logger.LogInformation("Mantra cache hit for user {UserId} on {Date}", user.Id, today);
            return Ok(mantra);
        }

        // No mantra yet — trigger generation and return empty
        logger.LogInformation("Mantra cache miss for user {UserId} on {Date} — enqueueing generation", user.Id, today);
        jobs.Enqueue<GenerateDailyMantraJob>(j => j.RunAsync(user.Id, today));

        return Ok(new { Content = (string?)null, Date = today });
    }
}
