using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Routes;

public static class InsightRoutes
{
    public static void MapInsightRoutes(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/insights").RequireAuthorization();

        group.MapGet("/", ListInsights);
        group.MapDelete("/{id:guid}", DeleteInsight);
    }

    private static async Task<IResult> ListInsights(
        ClaimsPrincipal principal, AppDbContext db,
        int page = 1, int pageSize = 20)
    {
        var clerkId = principal.FindFirstValue("sub");
        if (clerkId is null) return Results.Unauthorized();

        var user = await db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (user is null) return Results.Unauthorized();

        pageSize = Math.Clamp(pageSize, 1, 50);

        var insights = await db.SavedInsights
            .Where(i => i.UserId == user.Id)
            .OrderByDescending(i => i.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(i => new { i.Id, i.Content, i.SourceConversationId, i.SourceJournalId, i.CreatedAt })
            .ToListAsync();

        return Results.Ok(insights);
    }

    private static async Task<IResult> DeleteInsight(
        Guid id, ClaimsPrincipal principal, AppDbContext db)
    {
        var clerkId = principal.FindFirstValue("sub");
        if (clerkId is null) return Results.Unauthorized();

        var user = await db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (user is null) return Results.Unauthorized();

        var insight = await db.SavedInsights
            .FirstOrDefaultAsync(i => i.Id == id && i.UserId == user.Id);

        if (insight is null) return Results.NotFound();

        db.SavedInsights.Remove(insight);
        await db.SaveChangesAsync();
        return Results.NoContent();
    }
}
