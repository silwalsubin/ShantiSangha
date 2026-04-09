using Microsoft.EntityFrameworkCore;
using ShantiSangha.Wellness.Contracts;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Services;

public class CopingService(WellnessDbContext db) : ICopingService
{
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

    public IReadOnlyList<ExerciseEntry> GetExercises() => Catalog;

    public async Task<CopingSessionResponse?> LogSessionAsync(
        Guid userId, string slug, LogSessionRequest request, CancellationToken ct = default)
    {
        if (!Catalog.Any(e => e.Slug == slug))
            return null;

        var session = new CopingSession
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            ExerciseSlug = slug,
            DurationSeconds = request.DurationSeconds,
            Notes = request.Notes,
            CompletedAt = DateTime.UtcNow
        };

        db.CopingSessions.Add(session);
        await db.SaveChangesAsync(ct);

        return new CopingSessionResponse(session.Id, session.ExerciseSlug, session.DurationSeconds, session.CompletedAt);
    }

    public async Task<List<CopingSessionListItem>> ListSessionsAsync(
        Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        pageSize = Math.Clamp(pageSize, 1, 50);

        return await db.CopingSessions
            .Where(s => s.UserId == userId)
            .OrderByDescending(s => s.CompletedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(s => new CopingSessionListItem(s.Id, s.ExerciseSlug, s.DurationSeconds, s.Notes, s.CompletedAt))
            .ToListAsync(ct);
    }
}
