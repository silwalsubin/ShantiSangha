using System.Security.Claims;
using Hangfire;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;
using ShantiSangha.Infrastructure.Jobs;
using ShantiSangha.Infrastructure.Storage;

namespace ShantiSangha.Api.Routes;

public static class VoiceRoutes
{
    private static readonly HashSet<string> AllowedExtensions = ["mp3", "mp4", "m4a", "wav", "webm", "ogg"];

    public static void MapVoiceRoutes(this WebApplication app)
    {
        var group = app.MapGroup("/voice").RequireAuthorization();

        group.MapPost("/upload-url", GetUploadUrl);
        group.MapPost("/entries", CreateEntry);
        group.MapGet("/entries", ListEntries);
        group.MapGet("/entries/{id:guid}", GetEntry);
    }

    /// <summary>
    /// Step 1 — client requests a presigned PUT URL.
    /// Client uploads directly to R2, then calls POST /voice/entries.
    /// </summary>
    private static async Task<IResult> GetUploadUrl(
        ClaimsPrincipal principal,
        AppDbContext db,
        StorageService storage,
        GetUploadUrlRequest body)
    {
        var user = await GetUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        var ext = body.Extension.ToLower().TrimStart('.');
        if (!AllowedExtensions.Contains(ext))
            return Results.BadRequest($"Unsupported file type. Allowed: {string.Join(", ", AllowedExtensions)}");

        var objectKey = $"voice/{user.Id}/{Guid.NewGuid()}.{ext}";
        var contentType = ext switch
        {
            "mp3" => "audio/mpeg",
            "mp4" or "m4a" => "audio/mp4",
            "wav" => "audio/wav",
            "webm" => "audio/webm",
            "ogg" => "audio/ogg",
            _ => "audio/mp4"
        };

        var url = await storage.GetPresignedUploadUrlAsync(objectKey, contentType, TimeSpan.FromMinutes(15));

        return Results.Ok(new { UploadUrl = url, ObjectKey = objectKey });
    }

    /// <summary>
    /// Step 2 — after the client has uploaded to R2, register the entry
    /// and enqueue the transcription job.
    /// </summary>
    private static async Task<IResult> CreateEntry(
        ClaimsPrincipal principal,
        AppDbContext db,
        IBackgroundJobClient jobs,
        CreateVoiceEntryRequest body)
    {
        var user = await GetUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        if (string.IsNullOrWhiteSpace(body.ObjectKey))
            return Results.BadRequest("ObjectKey is required.");

        var entry = new VoiceEntry
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            StorageKey = body.ObjectKey,
            Status = VoiceEntryStatus.Pending,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.VoiceEntries.Add(entry);
        await db.SaveChangesAsync();

        jobs.Enqueue<TranscribeVoiceJob>(j => j.RunAsync(entry.Id));

        return Results.Created($"/voice/entries/{entry.Id}",
            new { entry.Id, entry.Status, entry.CreatedAt });
    }

    private static async Task<IResult> ListEntries(
        ClaimsPrincipal principal, AppDbContext db,
        int page = 1, int pageSize = 20)
    {
        var user = await GetUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        pageSize = Math.Clamp(pageSize, 1, 50);

        var entries = await db.VoiceEntries
            .Where(v => v.UserId == user.Id)
            .OrderByDescending(v => v.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(v => new
            {
                v.Id,
                v.Status,
                v.CreatedAt,
                v.UpdatedAt,
                HasTranscript = v.Transcript != null,
                v.DraftJournalId
            })
            .ToListAsync();

        return Results.Ok(entries);
    }

    private static async Task<IResult> GetEntry(
        Guid id, ClaimsPrincipal principal, AppDbContext db)
    {
        var user = await GetUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        var entry = await db.VoiceEntries
            .Where(v => v.Id == id && v.UserId == user.Id)
            .Select(v => new
            {
                v.Id,
                v.Status,
                v.Transcript,
                v.DraftJournalId,
                v.CreatedAt,
                v.UpdatedAt
            })
            .FirstOrDefaultAsync();

        return entry is null ? Results.NotFound() : Results.Ok(entry);
    }

    private static async Task<User?> GetUserAsync(ClaimsPrincipal principal, AppDbContext db)
    {
        var clerkId = principal.FindFirstValue("sub");
        if (clerkId is null) return null;
        return await db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
    }
}

public record GetUploadUrlRequest(string Extension);
public record CreateVoiceEntryRequest(string ObjectKey);
