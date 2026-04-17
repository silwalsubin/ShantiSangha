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
[Route("api/portrait")]
public class PortraitController(
    WellnessDbContext db,
    ICurrentUser currentUser,
    IBackgroundJobClient jobs,
    ILogger<PortraitController> logger) : ControllerBase
{
    /// <summary>
    /// Returns the user's portrait. If none exists or it's stale (>7 days),
    /// enqueues regeneration and returns what's available (or null).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var portrait = await db.Portraits
            .Where(p => p.UserId == user.Id)
            .Select(p => new { p.Content, p.CreatedAt })
            .FirstOrDefaultAsync(ct);

        // Regenerate if missing or older than 7 days
        var isStale = portrait is null
            || (DateTime.UtcNow - portrait.CreatedAt).TotalDays > 7;

        if (isStale)
        {
            logger.LogInformation("Portrait {Status} for user {UserId} — enqueueing generation",
                portrait is null ? "missing" : "stale", user.Id);
            jobs.Enqueue<GeneratePortraitJob>(j => j.RunAsync(user.Id));
        }

        return Ok(new
        {
            Content = portrait?.Content,
            GeneratedAt = portrait?.CreatedAt
        });
    }
}
