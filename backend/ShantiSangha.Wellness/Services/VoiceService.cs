using Microsoft.EntityFrameworkCore;
using ShantiSangha.Wellness.Contracts;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Models;
using ShantiSangha.Wellness.Storage;

namespace ShantiSangha.Wellness.Services;

public class VoiceService(WellnessDbContext db, StorageService storage) : IVoiceService
{
    private static readonly HashSet<string> AllowedExtensions = ["mp3", "mp4", "m4a", "wav", "webm", "ogg"];

    public async Task<UploadUrlResponse?> GetUploadUrlAsync(Guid userId, GetUploadUrlRequest request, CancellationToken ct = default)
    {
        var ext = request.Extension.ToLower().TrimStart('.');
        if (!AllowedExtensions.Contains(ext))
            return null;

        var objectKey = $"voice/{userId}/{Guid.NewGuid()}.{ext}";
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
        return new UploadUrlResponse(url, objectKey);
    }

    public async Task<VoiceEntryCreatedResponse> CreateEntryAsync(Guid userId, CreateVoiceEntryRequest request, CancellationToken ct = default)
    {
        var entry = new VoiceEntry
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            StorageKey = request.ObjectKey,
            Status = VoiceEntryStatus.Pending,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.VoiceEntries.Add(entry);
        await db.SaveChangesAsync(ct);

        return new VoiceEntryCreatedResponse(entry.Id, entry.Status.ToString(), entry.CreatedAt);
    }

    public async Task<List<VoiceEntryListItem>> ListEntriesAsync(Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        pageSize = Math.Clamp(pageSize, 1, 50);

        return await db.VoiceEntries
            .Where(v => v.UserId == userId)
            .OrderByDescending(v => v.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(v => new VoiceEntryListItem(
                v.Id,
                v.Status.ToString(),
                v.CreatedAt,
                v.UpdatedAt,
                v.Transcript != null,
                v.Transcript != null ? (v.Transcript.Length > 120 ? v.Transcript.Substring(0, 120) + "\u2026" : v.Transcript) : null,
                v.DraftJournalId))
            .ToListAsync(ct);
    }

    public async Task<VoiceEntryDetailResponse?> GetEntryAsync(Guid userId, Guid entryId, CancellationToken ct = default)
    {
        return await db.VoiceEntries
            .Where(v => v.Id == entryId && v.UserId == userId)
            .Select(v => new VoiceEntryDetailResponse(
                v.Id,
                v.Status.ToString(),
                v.Transcript,
                v.DraftJournalId,
                v.CreatedAt,
                v.UpdatedAt))
            .FirstOrDefaultAsync(ct);
    }
}
