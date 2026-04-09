using Microsoft.EntityFrameworkCore;
using ShantiSangha.Wellness.Contracts;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;

namespace ShantiSangha.Wellness.Services;

public class MoodService(WellnessDbContext db) : IMoodService
{
    public async Task<MoodCheckinResponse> CreateCheckinAsync(Guid userId, CreateMoodCheckinRequest request, CancellationToken ct = default)
    {
        var checkin = new MoodCheckin
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Score = request.Score,
            Notes = request.Notes,
            CreatedAt = DateTime.UtcNow
        };

        db.MoodCheckins.Add(checkin);
        await db.SaveChangesAsync(ct);

        return new MoodCheckinResponse(checkin.Id, checkin.Score, checkin.CreatedAt);
    }

    public async Task<List<MoodCheckinListItem>> ListCheckinsAsync(
        Guid userId, DateTime? from, DateTime? to,
        int page, int pageSize, CancellationToken ct = default)
    {
        pageSize = Math.Clamp(pageSize, 1, 100);
        var start = from ?? DateTime.UtcNow.AddDays(-30);
        var end = to ?? DateTime.UtcNow;

        return await db.MoodCheckins
            .Where(m => m.UserId == userId && m.CreatedAt >= start && m.CreatedAt <= end)
            .OrderByDescending(m => m.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(m => new MoodCheckinListItem(m.Id, m.Score, m.Notes, m.CreatedAt))
            .ToListAsync(ct);
    }

    public async Task<object> GetTrendsAsync(Guid userId, DateTime? from, DateTime? to, CancellationToken ct = default)
    {
        var start = from ?? DateTime.UtcNow.AddDays(-30);
        var end = to ?? DateTime.UtcNow;

        var checkins = await db.MoodCheckins
            .Where(m => m.UserId == userId && m.CreatedAt >= start && m.CreatedAt <= end)
            .OrderBy(m => m.CreatedAt)
            .ToListAsync(ct);

        if (checkins.Count == 0)
            return new { Average = (double?)null, Trend = (string?)null, DailyAverages = Array.Empty<object>() };

        // Group by day for chart data
        var dailyAverages = checkins
            .GroupBy(m => m.CreatedAt.Date)
            .Select(g => new { Date = g.Key, Average = g.Average(m => m.Score), Count = g.Count() })
            .OrderBy(d => d.Date)
            .ToList();

        // Simple trend: compare first half vs second half average
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

        return new
        {
            Average = checkins.Average(m => m.Score),
            Highest = checkins.Max(m => m.Score),
            Lowest = checkins.Min(m => m.Score),
            Trend = trend,
            TotalCheckins = checkins.Count,
            DailyAverages = dailyAverages
        };
    }
}
