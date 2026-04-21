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
    // Fallback window: show yesterday's (or day-before-yesterday's) reflection
    // when today's isn't ready yet. Beyond this, the fallback feels stale and
    // we'd rather show the "still arriving" copy than a reflection from a week ago.
    private const int FallbackMaxAgeDays = 3;

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
            .Select(r => new { r.Content, r.Date, Type = r.Type.ToString() })
            .FirstOrDefaultAsync(ct);

        if (reflection is not null)
        {
            logger.LogInformation("Reflection cache hit for user {UserId} on {Date}", user.Id, today);
            return Ok(new
            {
                Content = reflection.Content,
                Date = reflection.Date,
                Type = reflection.Type,
                Fallback = (object?)null,
            });
        }

        // Cache miss — enqueue generation, and return the most recent prior
        // reflection as a fallback so home is never empty while the job runs.
        // The client uses `fallback` to render yesterday's text with a subtle
        // "today's is being written" chip instead of a dead spinner.
        logger.LogInformation("Reflection cache miss for user {UserId} on {Date} — enqueueing generation", user.Id, today);
        jobs.Enqueue<GenerateDailyReflectionJob>(j => j.RunAsync(user.Id, today));

        var fallbackCutoff = today.AddDays(-FallbackMaxAgeDays);
        var fallback = await db.DailyReflections
            .Where(r => r.UserId == user.Id && r.Date < today && r.Date >= fallbackCutoff)
            .OrderByDescending(r => r.Date)
            .Select(r => new { r.Content, r.Date, Type = r.Type.ToString() })
            .FirstOrDefaultAsync(ct);

        return Ok(new
        {
            Content = (string?)null,
            Date = today,
            Type = (string?)null,
            Fallback = fallback,
        });
    }
}
