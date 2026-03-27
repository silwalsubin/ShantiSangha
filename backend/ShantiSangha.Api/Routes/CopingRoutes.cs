using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Routes;

public static class CopingRoutes
{
    // Static exercise catalog — no DB table needed until we want user-created exercises
    private static readonly IReadOnlyList<ExerciseEntry> Catalog =
    [
        new("box-breathing",        "Box Breathing",
            "Slow, structured breathing to calm the nervous system.",
            "breathing", 240),
        new("grounding-5-4-3-2-1",  "5-4-3-2-1 Grounding",
            "Use your senses to anchor yourself to the present moment.",
            "grounding", 300),
        new("body-scan",            "Body Scan",
            "Progressively relax each part of your body from head to toe.",
            "relaxation", 480),
        new("progressive-muscle",   "Progressive Muscle Relaxation",
            "Tense and release muscle groups to release physical tension.",
            "relaxation", 600),
        new("mindful-breathing",    "Mindful Breathing",
            "Simply observe your breath without trying to change it.",
            "mindfulness", 180),
        new("journaling-prompt",    "Reflective Journaling",
            "Write freely about what is on your mind right now.",
            "reflection", 0),
        new("cold-water",           "Cold Water Reset",
            "Splash cold water on your face to interrupt the stress response.",
            "grounding", 60),
        new("safe-place",           "Safe Place Visualisation",
            "Imagine a calm, safe space in vivid detail.",
            "visualisation", 300),
    ];

    public static void MapCopingRoutes(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/exercises").RequireAuthorization();

        group.MapGet("/", GetCatalog);
        group.MapPost("/{slug}/sessions", LogSession);
        group.MapGet("/sessions", ListSessions);
    }

    private static IResult GetCatalog() => Results.Ok(Catalog);

    private static async Task<IResult> LogSession(
        string slug,
        ClaimsPrincipal principal,
        AppDbContext db,
        LogSessionRequest body)
    {
        var user = await RouteHelper.GetOrCreateUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        if (!Catalog.Any(e => e.Slug == slug))
            return Results.NotFound("Exercise not found.");

        var session = new CopingSession
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            ExerciseSlug = slug,
            DurationSeconds = body.DurationSeconds,
            Notes = body.Notes,
            CompletedAt = DateTime.UtcNow
        };

        db.CopingSessions.Add(session);
        await db.SaveChangesAsync();

        return Results.Created($"/exercises/sessions/{session.Id}",
            new { session.Id, session.ExerciseSlug, session.DurationSeconds, session.CompletedAt });
    }

    private static async Task<IResult> ListSessions(
        ClaimsPrincipal principal, AppDbContext db,
        int page = 1, int pageSize = 20)
    {
        var user = await RouteHelper.GetOrCreateUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        pageSize = Math.Clamp(pageSize, 1, 50);

        var sessions = await db.CopingSessions
            .Where(s => s.UserId == user.Id)
            .OrderByDescending(s => s.CompletedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(s => new { s.Id, s.ExerciseSlug, s.DurationSeconds, s.Notes, s.CompletedAt })
            .ToListAsync();

        return Results.Ok(sessions);
    }
}

public record ExerciseEntry(string Slug, string Name, string Description, string Category, int DefaultDurationSeconds);
public record LogSessionRequest(int DurationSeconds, string? Notes);
