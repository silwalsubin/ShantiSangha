using Microsoft.EntityFrameworkCore;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;
using ShantiSangha.Wellness.Data;

namespace ShantiSangha.Wellness.Services;

public class MoodQueryService(WellnessDbContext db) : IMoodQueryService
{
    public async Task<MoodSummaryDto?> GetRecentMoodSummaryAsync(Guid userId, int days = 7, CancellationToken ct = default)
    {
        var since = DateTime.UtcNow.AddDays(-days);

        var checkins = await db.MoodCheckins
            .Where(m => m.UserId == userId && m.CreatedAt >= since)
            .OrderBy(m => m.CreatedAt)
            .ToListAsync(ct);

        if (checkins.Count == 0) return null;

        var avg = checkins.Average(m => m.Score);

        var midpoint = checkins.Count / 2;
        var trend = "stable";
        if (midpoint > 0)
        {
            var firstHalfAvg = checkins.Take(midpoint).Average(m => m.Score);
            var secondHalfAvg = checkins.Skip(midpoint).Average(m => m.Score);
            var diff = secondHalfAvg - firstHalfAvg;
            trend = diff switch
            {
                > 0.5 => "improving",
                < -0.5 => "declining",
                _ => "stable"
            };
        }

        return new MoodSummaryDto(avg, checkins.Count, trend);
    }
}
