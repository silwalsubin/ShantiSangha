using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Routes;

public static class MoodRoutes
{
    public static void MapMoodRoutes(this WebApplication app)
    {
        var group = app.MapGroup("/moods").RequireAuthorization();

        group.MapPost("/", CreateCheckin);
        group.MapGet("/", ListCheckins);
        group.MapGet("/trends", GetTrends);
    }

    private static async Task<IResult> CreateCheckin(
        ClaimsPrincipal principal, AppDbContext db,
        CreateMoodCheckinRequest body)
    {
        var user = await GetUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        if (body.Score is < 1 or > 10)
            return Results.BadRequest("Score must be between 1 and 10.");

        var checkin = new MoodCheckin
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Score = body.Score,
            Notes = body.Notes,
            CreatedAt = DateTime.UtcNow
        };

        db.MoodCheckins.Add(checkin);
        await db.SaveChangesAsync();

        return Results.Created($"/moods/{checkin.Id}", new { checkin.Id, checkin.Score, checkin.CreatedAt });
    }

    private static async Task<IResult> ListCheckins(
        ClaimsPrincipal principal, AppDbContext db,
        DateTime? from = null, DateTime? to = null,
        int page = 1, int pageSize = 30)
    {
        var user = await GetUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        pageSize = Math.Clamp(pageSize, 1, 100);
        var start = from ?? DateTime.UtcNow.AddDays(-30);
        var end = to ?? DateTime.UtcNow;

        var checkins = await db.MoodCheckins
            .Where(m => m.UserId == user.Id && m.CreatedAt >= start && m.CreatedAt <= end)
            .OrderByDescending(m => m.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(m => new { m.Id, m.Score, m.Notes, m.CreatedAt })
            .ToListAsync();

        return Results.Ok(checkins);
    }

    private static async Task<IResult> GetTrends(
        ClaimsPrincipal principal, AppDbContext db,
        DateTime? from = null, DateTime? to = null)
    {
        var user = await GetUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        var start = from ?? DateTime.UtcNow.AddDays(-30);
        var end = to ?? DateTime.UtcNow;

        var checkins = await db.MoodCheckins
            .Where(m => m.UserId == user.Id && m.CreatedAt >= start && m.CreatedAt <= end)
            .OrderBy(m => m.CreatedAt)
            .ToListAsync();

        if (checkins.Count == 0)
            return Results.Ok(new { Average = (double?)null, Trend = (string?)null, DailyAverages = Array.Empty<object>() });

        // Group by day for chart data
        var dailyAverages = checkins
            .GroupBy(m => m.CreatedAt.Date)
            .Select(g => new { Date = g.Key, Average = g.Average(m => m.Score), Count = g.Count() })
            .OrderBy(d => d.Date)
            .ToList();

        // Simple trend: compare first half vs second half average
        var midpoint = checkins.Count / 2;
        var firstHalfAvg = checkins.Take(midpoint).Average(m => m.Score);
        var secondHalfAvg = checkins.Skip(midpoint).Average(m => m.Score);
        var diff = secondHalfAvg - firstHalfAvg;
        var trend = diff switch
        {
            > 0.5 => "improving",
            < -0.5 => "declining",
            _ => "stable"
        };

        return Results.Ok(new
        {
            Average = checkins.Average(m => m.Score),
            Highest = checkins.Max(m => m.Score),
            Lowest = checkins.Min(m => m.Score),
            Trend = trend,
            TotalCheckins = checkins.Count,
            DailyAverages = dailyAverages
        });
    }

    private static async Task<User?> GetUserAsync(ClaimsPrincipal principal, AppDbContext db)
    {
        var clerkId = principal.FindFirstValue("sub");
        if (clerkId is null) return null;
        return await db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
    }
}

public record CreateMoodCheckinRequest(int Score, string? Notes);
