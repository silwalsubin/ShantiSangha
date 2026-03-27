using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;
using ShantiSangha.Infrastructure.Storage;

namespace ShantiSangha.Infrastructure.Jobs;

public class TranscribeVoiceJob(
    AppDbContext db,
    StorageService storage,
    IHttpClientFactory httpClientFactory,
    ILogger<TranscribeVoiceJob> logger)
{
    public async Task RunAsync(Guid voiceEntryId)
    {
        var entry = await db.VoiceEntries.FindAsync(voiceEntryId);
        if (entry is null || entry.Status != VoiceEntryStatus.Pending) return;

        entry.Status = VoiceEntryStatus.Transcribing;
        entry.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        try
        {
            // Download audio from R2
            await using var audioStream = await storage.DownloadAsync(entry.StorageKey);

            // Determine file extension from storage key for the form data
            var extension = Path.GetExtension(entry.StorageKey).TrimStart('.') is { Length: > 0 } ext ? ext : "mp4";

            // Call OpenAI Whisper API
            var transcript = await TranscribeAsync(audioStream, extension);

            if (string.IsNullOrWhiteSpace(transcript))
            {
                logger.LogWarning("Whisper returned empty transcript for entry {Id}", voiceEntryId);
                entry.Status = VoiceEntryStatus.Failed;
                entry.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync();
                return;
            }

            entry.Transcript = transcript;
            entry.Status = VoiceEntryStatus.Completed;
            entry.UpdatedAt = DateTime.UtcNow;

            // Create a journal draft from the transcript
            var draft = new Journal
            {
                Id = Guid.NewGuid(),
                UserId = entry.UserId,
                Title = $"Voice note — {entry.CreatedAt:MMM d, yyyy}",
                Content = transcript,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            };

            db.Journals.Add(draft);
            entry.DraftJournalId = draft.Id;

            await db.SaveChangesAsync();

            logger.LogInformation("Transcribed voice entry {Id} → journal draft {JournalId}", voiceEntryId, draft.Id);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to transcribe voice entry {Id}", voiceEntryId);
            entry.Status = VoiceEntryStatus.Failed;
            entry.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }
    }

    private async Task<string?> TranscribeAsync(Stream audio, string extension)
    {
        var client = httpClientFactory.CreateClient("OpenAI");

        using var form = new MultipartFormDataContent();
        var audioContent = new StreamContent(audio);
        audioContent.Headers.ContentType = new MediaTypeHeaderValue(GetMimeType(extension));
        form.Add(audioContent, "file", $"audio.{extension}");
        form.Add(new StringContent("whisper-1"), "model");
        form.Add(new StringContent("en"), "language");

        var response = await client.PostAsync("https://api.openai.com/v1/audio/transcriptions", form);
        if (!response.IsSuccessStatusCode)
        {
            logger.LogError("Whisper API returned {StatusCode}", response.StatusCode);
            return null;
        }

        using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return doc.RootElement.GetProperty("text").GetString();
    }

    private static string GetMimeType(string extension) => extension.ToLower() switch
    {
        "mp3" => "audio/mpeg",
        "mp4" or "m4a" => "audio/mp4",
        "wav" => "audio/wav",
        "webm" => "audio/webm",
        "ogg" => "audio/ogg",
        _ => "audio/mp4"
    };
}
