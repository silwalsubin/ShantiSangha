using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Routes;

public static class UserRoutes
{
    public static void MapUserRoutes(this WebApplication app)
    {
        var group = app.MapGroup("/me").RequireAuthorization();

        group.MapGet("/", GetMe);
        group.MapPatch("/", UpdateMe);
    }

    private static async Task<IResult> GetMe(ClaimsPrincipal principal, AppDbContext db)
    {
        var clerkId = principal.FindFirstValue("sub");
        if (clerkId is null) return Results.Unauthorized();

        var user = await db.Users
            .Include(u => u.Profile)
            .FirstOrDefaultAsync(u => u.ClerkId == clerkId);

        if (user is null) return Results.NotFound();

        return Results.Ok(new
        {
            user.Id,
            user.Email,
            user.CreatedAt,
            Profile = user.Profile is null ? null : new
            {
                user.Profile.DisplayName,
                user.Profile.Timezone,
                user.Profile.OnboardingCompleted
            }
        });
    }

    private static async Task<IResult> UpdateMe(
        ClaimsPrincipal principal,
        AppDbContext db,
        UpdateMeRequest body)
    {
        var clerkId = principal.FindFirstValue("sub");
        if (clerkId is null) return Results.Unauthorized();

        var user = await db.Users
            .Include(u => u.Profile)
            .FirstOrDefaultAsync(u => u.ClerkId == clerkId);

        if (user is null) return Results.NotFound();
        if (user.Profile is null) return Results.Problem("Profile not found");

        if (body.DisplayName is not null) user.Profile.DisplayName = body.DisplayName;
        if (body.Timezone is not null) user.Profile.Timezone = body.Timezone;
        if (body.OnboardingCompleted is not null) user.Profile.OnboardingCompleted = body.OnboardingCompleted.Value;

        user.Profile.UpdatedAt = DateTime.UtcNow;
        user.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        return Results.NoContent();
    }
}

public record UpdateMeRequest(string? DisplayName, string? Timezone, bool? OnboardingCompleted);
