using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Insights.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Insights.Controllers;

[ApiController]
[Authorize]
[Route("api/search")]
public class SearchController(
    SemanticSearchService searchService,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Search(
        [FromQuery] string q,
        [FromQuery] string type = "all",
        [FromQuery] int limit = 10,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(q))
            return BadRequest("Query parameter 'q' is required.");

        limit = Math.Clamp(limit, 1, 50);

        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var results = type.ToLower() switch
        {
            "insights" => await searchService.SearchInsightsAsync(user.Id, q, limit, ct),
            "journals" => await searchService.SearchJournalsAsync(user.Id, q, limit, ct),
            _ => await searchService.SearchAllAsync(user.Id, q, limit, ct)
        };

        return Ok(new
        {
            Query = q,
            Type = type,
            Results = results
        });
    }
}
