using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Services;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Routes;

public static class SearchRoutes
{
    public static void MapSearchRoutes(this IEndpointRouteBuilder app)
    {
        app.MapGet("/search", Search).RequireAuthorization();
    }

    private static async Task<IResult> Search(
        ClaimsPrincipal principal,
        AppDbContext db,
        ISemanticSearchService searchService,
        string q,
        string type = "all",   // "insights" | "journals" | "all"
        int limit = 10)
    {
        if (string.IsNullOrWhiteSpace(q))
            return Results.BadRequest("Query parameter 'q' is required.");

        limit = Math.Clamp(limit, 1, 50);

        var clerkId = principal.FindFirstValue("sub");
        if (clerkId is null) return Results.Unauthorized();

        var user = await db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (user is null) return Results.Unauthorized();

        var results = type.ToLower() switch
        {
            "insights" => await searchService.SearchInsightsAsync(user.Id, q, limit),
            "journals"  => await searchService.SearchJournalsAsync(user.Id, q, limit),
            _           => await searchService.SearchAllAsync(user.Id, q, limit)
        };

        return Results.Ok(new
        {
            Query = q,
            Type = type,
            Results = results
        });
    }
}
