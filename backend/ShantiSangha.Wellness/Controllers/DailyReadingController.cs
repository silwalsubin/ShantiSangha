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
[Route("api/daily-reading")]
public class DailyReadingController(
    WellnessDbContext db,
    ICurrentUser currentUser,
    IBackgroundJobClient jobs,
    ILogger<DailyReadingController> logger) : ControllerBase
{
    /// <summary>
    /// Returns today's daily reading for the user. If the reading hasn't been
    /// generated yet (e.g. user opened app before the midnight scheduler ran),
    /// enqueues generation and returns null. Client should poll for result.
    /// </summary>
    [HttpGet("today")]
    public async Task<IActionResult> GetToday([FromQuery] string? date, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var reading = await db.DailyReadings
            .Where(r => r.UserId == user.Id && r.Date == today)
            .Select(r => new { r.Content, r.Date })
            .FirstOrDefaultAsync(ct);

        if (reading is not null)
        {
            return Ok(new { Content = reading.Content, Date = reading.Date });
        }

        logger.LogInformation("Daily reading missing for user {UserId} on {Date} — enqueueing generation", user.Id, today);
        jobs.Enqueue<GenerateDailyReadingJob>(j => j.RunAsync(user.Id, today));

        return Ok(new { Content = (string?)null, Date = today });
    }
}
