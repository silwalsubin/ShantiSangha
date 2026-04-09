using Microsoft.EntityFrameworkCore;
using ShantiSangha.Journal.Data;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Models;

namespace ShantiSangha.Journal.Services;

public class JournalQueryService(JournalDbContext db) : IJournalQueryService
{
    public async Task<JournalContentDto?> GetJournalContentAsync(
        Guid journalId, CancellationToken ct = default)
    {
        return await db.Journals
            .Where(j => j.Id == journalId)
            .Select(j => new JournalContentDto(j.Id, j.UserId, j.Title, j.Content, j.CreatedAt))
            .FirstOrDefaultAsync(ct);
    }
}
