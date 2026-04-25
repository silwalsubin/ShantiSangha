using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Identity.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Controllers;

[ApiController]
[Authorize]
[Route("api/users")]
public class UserSearchController(
    IUserSearchService search,
    ICurrentUser currentUser) : ControllerBase
{
    [HttpGet("search")]
    public async Task<IActionResult> Search(
        [FromQuery] string? q = null,
        [FromQuery] string? location = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        // Refuse a full-table dump. At least one filter must be present —
        // search is "find by name and/or location", not "list every user".
        var hasQ = !string.IsNullOrWhiteSpace(q);
        var hasLoc = !string.IsNullOrWhiteSpace(location);
        if (!hasQ && !hasLoc)
        {
            return BadRequest(new
            {
                error = "missing_filter",
                message = "At least one of `q` or `location` must be provided."
            });
        }

        var result = await search.SearchAsync(user.Id, q, location, page, pageSize, ct);
        return Ok(result);
    }
}
