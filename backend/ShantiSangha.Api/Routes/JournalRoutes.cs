using Hangfire;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Api.Services;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;
using ShantiSangha.Infrastructure.Jobs;

namespace ShantiSangha.Api.Routes;

public static class JournalRoutes
{
    public static void MapJournalRoutes(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/journals").RequireAuthorization();

        group.MapGet("/", ListJournals);
        group.MapPost("/", CreateJournal);
        group.MapGet("/{id:guid}", GetJournal);
        group.MapPatch("/{id:guid}", UpdateJournal);
        group.MapDelete("/{id:guid}", DeleteJournal);
    }

    private static async Task<IResult> ListJournals(
        ICurrentUser currentUser, AppDbContext db,
        int page = 1, int pageSize = 20)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        pageSize = Math.Clamp(pageSize, 1, 50);

        var journals = await db.Journals
            .Where(j => j.UserId == user.Id)
            .OrderByDescending(j => j.UpdatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(j => new { j.Id, j.Title, j.CreatedAt, j.UpdatedAt,
                Preview = j.Content.Length > 120 ? j.Content.Substring(0, 120) + "…" : j.Content })
            .ToListAsync();

        return Results.Ok(journals);
    }

    private static async Task<IResult> CreateJournal(
        ICurrentUser currentUser, AppDbContext db,
        IBackgroundJobClient jobs,
        CreateJournalRequest body)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var journal = new Journal
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Title = body.Title,
            Content = body.Content,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.Journals.Add(journal);
        await db.SaveChangesAsync();

        // Enqueue embedding + summary + insight extraction
        jobs.Enqueue<GenerateEmbeddingJob>(j => j.RunForJournalAsync(journal.Id));
        var summaryJobId = jobs.Enqueue<GenerateSummaryJob>(j => j.RunForJournalAsync(journal.Id, user.Id));
        jobs.ContinueJobWith<ExtractInsightsJob>(summaryJobId, j =>
            j.RunAsync(journal.Id, SummarySourceType.Journal, user.Id));

        return Results.Created($"/journals/{journal.Id}", new { journal.Id, journal.Title, journal.CreatedAt });
    }

    private static async Task<IResult> GetJournal(
        Guid id, ICurrentUser currentUser, AppDbContext db)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var journal = await db.Journals
            .Where(j => j.Id == id && j.UserId == user.Id)
            .Select(j => new { j.Id, j.Title, j.Content, j.CreatedAt, j.UpdatedAt })
            .FirstOrDefaultAsync();

        return journal is null ? Results.NotFound() : Results.Ok(journal);
    }

    private static async Task<IResult> UpdateJournal(
        Guid id, ICurrentUser currentUser, AppDbContext db,
        UpdateJournalRequest body)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var journal = await db.Journals
            .FirstOrDefaultAsync(j => j.Id == id && j.UserId == user.Id);

        if (journal is null) return Results.NotFound();

        if (body.Title is not null) journal.Title = body.Title;
        if (body.Content is not null) journal.Content = body.Content;
        journal.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync();
        return Results.NoContent();
    }

    private static async Task<IResult> DeleteJournal(
        Guid id, ICurrentUser currentUser, AppDbContext db)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Results.Unauthorized();

        var journal = await db.Journals
            .FirstOrDefaultAsync(j => j.Id == id && j.UserId == user.Id);

        if (journal is null) return Results.NotFound();

        db.Journals.Remove(journal);
        await db.SaveChangesAsync();
        return Results.NoContent();
    }
}

public record CreateJournalRequest(string Title, string Content);
public record UpdateJournalRequest(string? Title, string? Content);
