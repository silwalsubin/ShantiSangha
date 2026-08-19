using Microsoft.EntityFrameworkCore;
using ShantiSangha.Journal.Contracts;
using ShantiSangha.Journal.Data;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Journal.Services;

public class JournalService(JournalDbContext db, IEventBus eventBus) : IJournalService
{
    public async Task<IReadOnlyList<JournalListItem>> ListAsync(
        Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        pageSize = Math.Clamp(pageSize, 1, 50);

        return await db.Journals
            .Where(j => j.UserId == userId)
            .OrderByDescending(j => j.UpdatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(j => new JournalListItem(
                j.Id,
                j.Title,
                j.CreatedAt,
                j.UpdatedAt,
                j.Content.Length > 120 ? j.Content.Substring(0, 120) + "\u2026" : j.Content))
            .ToListAsync(ct);
    }

    public async Task<JournalCreatedResponse> CreateAsync(
        Guid userId, CreateJournalRequest request, CancellationToken ct = default)
    {
        var journal = new Models.Journal
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            Title = request.Title,
            Content = request.Content,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.Journals.Add(journal);
        await db.SaveChangesAsync(ct);

        await eventBus.PublishAsync(new JournalCreatedEvent(journal.Id, userId), ct);

        return new JournalCreatedResponse(journal.Id, journal.Title, journal.CreatedAt);
    }

    public async Task<JournalDetailResponse?> GetByIdAsync(
        Guid id, Guid userId, CancellationToken ct = default)
    {
        return await db.Journals
            .Where(j => j.Id == id && j.UserId == userId)
            .Select(j => new JournalDetailResponse(j.Id, j.Title, j.Content, j.CreatedAt, j.UpdatedAt))
            .FirstOrDefaultAsync(ct);
    }

    public async Task<bool> UpdateAsync(
        Guid id, Guid userId, UpdateJournalRequest request, CancellationToken ct = default)
    {
        var journal = await db.Journals
            .FirstOrDefaultAsync(j => j.Id == id && j.UserId == userId, ct);

        if (journal is null) return false;

        if (request.Title is not null) journal.Title = request.Title;
        if (request.Content is not null) journal.Content = request.Content;
        journal.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);

        await eventBus.PublishAsync(new JournalUpdatedEvent(journal.Id, userId), ct);

        return true;
    }

    public async Task<bool> DeleteAsync(
        Guid id, Guid userId, CancellationToken ct = default)
    {
        var journal = await db.Journals
            .FirstOrDefaultAsync(j => j.Id == id && j.UserId == userId, ct);

        if (journal is null) return false;

        db.Journals.Remove(journal);
        await db.SaveChangesAsync(ct);

        await eventBus.PublishAsync(new JournalDeletedEvent(id, userId), ct);

        return true;
    }

    internal async Task HandleVoiceTranscribedAsync(
        VoiceTranscribedEvent e, CancellationToken ct = default)
    {
        var journal = new Models.Journal
        {
            Id = Guid.NewGuid(),
            UserId = e.UserId,
            Title = string.Empty,
            Content = e.Transcript,
            CreatedAt = e.CreatedAt,
            UpdatedAt = DateTime.UtcNow
        };

        db.Journals.Add(journal);
        await db.SaveChangesAsync(ct);

        // Draft event links the voice entry to its auto-created journal (for UI ownership).
        await eventBus.PublishAsync(new JournalDraftCreatedEvent(e.VoiceEntryId, journal.Id), ct);

        // Created event keeps voice-backed journal drafts available to any
        // subscriber that reacts to new journal entries.
        await eventBus.PublishAsync(new JournalCreatedEvent(journal.Id, e.UserId), ct);
    }
}
