using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Jyotish.Controllers;

[ApiController]
[Authorize]
[Route("api/jyotish/reading")]
public class ChartReadingController(
    ICurrentUser currentUser,
    IChartReadingService readingService,
    ILogger<ChartReadingController> logger) : ControllerBase
{
    /// <summary>
    /// Returns the user's pre-composed chart reading. Lazy-generates on
    /// first access or when the cached hash is stale (birth details changed).
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> GetReading(
        [FromQuery] bool force = false,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        ChartReading? reading = null;
        if (!force)
        {
            try
            {
                reading = await readingService.GetAsync(user.Id, ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to load cached chart reading for user {UserId}", user.Id);
            }
        }

        if (reading is null)
        {
            try
            {
                reading = await readingService.GenerateAsync(user.Id, ct);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Chart reading generation failed for user {UserId}", user.Id);
                return StatusCode(500, new { error = "reading generation failed" });
            }
        }

        return Ok(new
        {
            sections = reading.Sections,
            generatedAt = reading.GeneratedAt,
            isComplete = reading.IsComplete,
        });
    }

    /// <summary>
    /// Invalidates the cached reading. Next GET will regenerate.
    /// </summary>
    [HttpDelete]
    public async Task<IActionResult> InvalidateReading(CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        await readingService.InvalidateAsync(user.Id, ct);
        return NoContent();
    }
}
