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
[Route("api/reflection")]
public class ReflectionController(
    WellnessDbContext db,
    ICurrentUser currentUser,
    IBackgroundJobClient jobs,
    ILogger<ReflectionController> logger) : ControllerBase
{
    [HttpGet("today")]
    public async Task<IActionResult> GetToday([FromQuery] string? date, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var today = date is not null && DateOnly.TryParse(date, out var parsed)
            ? parsed
            : DateOnly.FromDateTime(DateTime.UtcNow);

        var reflection = await db.DailyReflections
            .Where(r => r.UserId == user.Id && r.Date == today)
            .Select(r => new { r.Content, r.Date })
            .FirstOrDefaultAsync(ct);

        if (reflection is not null)
        {
            logger.LogInformation("Reflection cache hit for user {UserId} on {Date}", user.Id, today);
            return Ok(reflection);
        }

        logger.LogInformation("Reflection cache miss for user {UserId} on {Date} — enqueueing generation", user.Id, today);
        jobs.Enqueue<GenerateDailyReflectionJob>(j => j.RunAsync(user.Id, today));

        return Ok(new { Content = (string?)null, Date = today });
    }
}
