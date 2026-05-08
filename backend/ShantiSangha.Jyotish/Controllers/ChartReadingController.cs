using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using ShantiSangha.Jyotish.Services;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Jyotish.Controllers;

[ApiController]
[Authorize]
[Route("api/jyotish/reading")]
public class ChartReadingController(
    ICurrentUser currentUser,
    IChartReadingService readingService,
    IPairChartReadingService pairReadingService,
    IBirthDetailShareService shareService,
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

    /// <summary>
    /// Returns the viewer's private 4-section reading of the specified subject.
    /// Gated by an active BirthDetailShare grant from subject to viewer; without
    /// that grant returns 403 even if the viewer knows the subject's user ID.
    /// </summary>
    [HttpGet("of/{subjectUserId:guid}")]
    public async Task<IActionResult> GetPairReading(
        Guid subjectUserId,
        [FromQuery] bool force = false,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        if (user.Id == subjectUserId)
            return BadRequest(new { error = "use the solo /reading endpoint for your own chart" });

        var hasAccess = await shareService.HasAccessAsync(user.Id, subjectUserId, ct);
        if (!hasAccess) return Forbid();

        PairChartReading? reading = null;
        if (!force)
        {
            try
            {
                reading = await pairReadingService.GetAsync(user.Id, subjectUserId, ct);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex,
                    "Failed to load cached pair reading viewer={Viewer} subject={Subject}",
                    user.Id, subjectUserId);
            }
        }

        if (reading is null)
        {
            try
            {
                reading = await pairReadingService.GenerateAsync(user.Id, subjectUserId, ct);
            }
            catch (InvalidOperationException ex)
            {
                return UnprocessableEntity(new { error = ex.Message });
            }
            catch (Exception ex)
            {
                logger.LogError(ex,
                    "Pair reading generation failed viewer={Viewer} subject={Subject}",
                    user.Id, subjectUserId);
                return StatusCode(500, new { error = "pair reading generation failed" });
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
    /// Invalidates the cached pair reading for this viewer→subject pair.
    /// Useful for "regenerate" UX or after the underlying share is revoked.
    /// </summary>
    [HttpDelete("of/{subjectUserId:guid}")]
    public async Task<IActionResult> InvalidatePairReading(Guid subjectUserId, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        await pairReadingService.InvalidateAsync(user.Id, subjectUserId, ct);
        return NoContent();
    }
}
