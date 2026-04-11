using Hangfire;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
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
    IBackgroundJobClient jobs) : ControllerBase
{
    [HttpGet("today")]
    public async Task<IActionResult> GetToday(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        var mantra = await db.DailyMantras
            .Where(m => m.UserId == user.Id && m.Date == today)
            .Select(m => new { m.Content, m.Date })
            .FirstOrDefaultAsync(ct);

        if (mantra is not null)
            return Ok(mantra);

        // No mantra yet — trigger generation and return empty
        jobs.Enqueue<GenerateDailyMantraJob>(j => j.RunAsync(user.Id));

        return Ok(new { Content = (string?)null, Date = today });
    }
}
