using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Memory.Contracts;
using ShantiSangha.Memory.Data;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Memory.Controllers;

[ApiController]
[Authorize]
[Route("api/memory")]
public class MemoryController(MemoryDbContext db, ICurrentUser currentUser) : ControllerBase
{
    /// Quiet continuity for Home: on how many of the last 7 local days did the
    /// user reflect (journal, voice note, or substantive companion message)?
    /// `tzOffsetMinutes` is the client's offset from UTC (positive east) so
    /// "days" match the user's calendar, not the server's.
    [HttpGet("presence")]
    [ProducesResponseType(typeof(PresenceResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetPresence(
        [FromQuery] int tzOffsetMinutes = 0, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        const int windowDays = 7;
        tzOffsetMinutes = Math.Clamp(tzOffsetMinutes, -14 * 60, 14 * 60);

        var todayLocal = DateTime.UtcNow.AddMinutes(tzOffsetMinutes).Date;
        var windowStartLocal = todayLocal.AddDays(-(windowDays - 1));
        var utcFloor = windowStartLocal.AddMinutes(-tzOffsetMinutes);

        var occurredUtc = await db.MemoryChunks
            .Where(c => c.UserId == user.Id && c.OccurredAt >= utcFloor)
            .Select(c => c.OccurredAt)
            .ToListAsync(ct);

        var localDays = occurredUtc
            .Select(t => t.AddMinutes(tzOffsetMinutes).Date)
            .Where(d => d >= windowStartLocal && d <= todayLocal)
            .Distinct()
            .ToList();

        return Ok(new PresenceResponse(
            DaysReflected: localDays.Count,
            WindowDays: windowDays,
            ReflectedToday: localDays.Contains(todayLocal)));
    }
}
