using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Insights.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Insights.Controllers;

[ApiController]
[Authorize]
[Route("api/insights")]
public class InsightsController(
    InsightService insightService,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> ListInsights(
        int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var insights = await insightService.ListInsightsAsync(user.Id, page, pageSize, ct);
        return Ok(insights);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteInsight(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var deleted = await insightService.DeleteInsightAsync(id, user.Id, ct);
        return deleted ? NoContent() : NotFound();
    }
}
