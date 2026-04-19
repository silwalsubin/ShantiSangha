using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Jyotish.Data;
using ShantiSangha.Jyotish.Models;
using ShantiSangha.Jyotish.Services;

namespace ShantiSangha.Jyotish.Controllers;

/// <summary>
/// Administrative ingestion for the Jyotish corpus. Accepts a source-cited
/// passage (or a batch), generates the embedding, and inserts/upserts into
/// the corpus table. Idempotent by PassageId.
///
/// This endpoint is intentionally permissive on auth right now — we'll gate
/// it behind an admin policy before it sees production traffic.
/// </summary>
[ApiController]
[AllowAnonymous]
[AdminKeyAuthorize]
[Route("api/jyotish/ingest")]
public class JyotishIngestController(
    JyotishDbContext db,
    JyotishKnowledgeService knowledge) : ControllerBase
{
    public record IngestPassageDto(
        string Id,
        string SignatureType,
        List<string> Signatures,
        string Title,
        string Content,
        List<string> Themes,
        string Polarity,
        string Scope,
        string SourceBook,
        string SourceAuthor,
        int SourceYear,
        string SourceLicense,
        string? SourceChapter,
        string? SourceVerse,
        string RawSourceExcerpt,
        string Source);

    [HttpPost]
    public async Task<IActionResult> IngestOne(
        [FromBody] IngestPassageDto dto,
        CancellationToken ct)
    {
        if (!Validate(dto, out var error)) return BadRequest(new { error });

        var existing = await db.Passages.FirstOrDefaultAsync(p => p.PassageId == dto.Id, ct);
        var embeddingText = BuildEmbeddingText(dto);
        var embedding = await knowledge.GenerateEmbeddingAsync(embeddingText, ct);

        if (existing is null)
        {
            var entity = new JyotishPassageEntity
            {
                Id = Guid.NewGuid(),
                PassageId = dto.Id,
                SignatureType = dto.SignatureType,
                Signatures = dto.Signatures.Select(s => s.Trim().ToLowerInvariant()).Distinct().ToList(),
                Title = dto.Title,
                Content = dto.Content,
                Themes = dto.Themes ?? [],
                Polarity = string.IsNullOrWhiteSpace(dto.Polarity) ? "mixed" : dto.Polarity,
                Scope = string.IsNullOrWhiteSpace(dto.Scope) ? "lifetime" : dto.Scope,
                SourceBook = dto.SourceBook,
                SourceAuthor = dto.SourceAuthor,
                SourceYear = dto.SourceYear,
                SourceLicense = dto.SourceLicense,
                SourceChapter = dto.SourceChapter,
                SourceVerse = dto.SourceVerse,
                RawSourceExcerpt = dto.RawSourceExcerpt,
                Source = dto.Source,
                Embedding = embedding,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow,
            };
            db.Passages.Add(entity);
        }
        else
        {
            existing.SignatureType = dto.SignatureType;
            existing.Signatures = dto.Signatures.Select(s => s.Trim().ToLowerInvariant()).Distinct().ToList();
            existing.Title = dto.Title;
            existing.Content = dto.Content;
            existing.Themes = dto.Themes ?? [];
            existing.Polarity = string.IsNullOrWhiteSpace(dto.Polarity) ? "mixed" : dto.Polarity;
            existing.Scope = string.IsNullOrWhiteSpace(dto.Scope) ? "lifetime" : dto.Scope;
            existing.SourceBook = dto.SourceBook;
            existing.SourceAuthor = dto.SourceAuthor;
            existing.SourceYear = dto.SourceYear;
            existing.SourceLicense = dto.SourceLicense;
            existing.SourceChapter = dto.SourceChapter;
            existing.SourceVerse = dto.SourceVerse;
            existing.RawSourceExcerpt = dto.RawSourceExcerpt;
            existing.Source = dto.Source;
            existing.Embedding = embedding;
            existing.UpdatedAt = DateTime.UtcNow;
        }

        await db.SaveChangesAsync(ct);
        return Ok(new { id = dto.Id, action = existing is null ? "inserted" : "updated" });
    }

    [HttpPost("batch")]
    public async Task<IActionResult> IngestBatch(
        [FromBody] List<IngestPassageDto> dtos,
        CancellationToken ct)
    {
        var results = new List<object>();
        foreach (var dto in dtos)
        {
            if (!Validate(dto, out var error))
            {
                results.Add(new { id = dto.Id, status = "invalid", error });
                continue;
            }

            var existing = await db.Passages.FirstOrDefaultAsync(p => p.PassageId == dto.Id, ct);
            var embeddingText = BuildEmbeddingText(dto);
            var embedding = await knowledge.GenerateEmbeddingAsync(embeddingText, ct);

            if (existing is null)
            {
                db.Passages.Add(new JyotishPassageEntity
                {
                    Id = Guid.NewGuid(),
                    PassageId = dto.Id,
                    SignatureType = dto.SignatureType,
                    Signatures = dto.Signatures.Select(s => s.Trim().ToLowerInvariant()).Distinct().ToList(),
                    Title = dto.Title,
                    Content = dto.Content,
                    Themes = dto.Themes ?? [],
                    Polarity = string.IsNullOrWhiteSpace(dto.Polarity) ? "mixed" : dto.Polarity,
                    Scope = string.IsNullOrWhiteSpace(dto.Scope) ? "lifetime" : dto.Scope,
                    SourceBook = dto.SourceBook,
                    SourceAuthor = dto.SourceAuthor,
                    SourceYear = dto.SourceYear,
                    SourceLicense = dto.SourceLicense,
                    SourceChapter = dto.SourceChapter,
                    SourceVerse = dto.SourceVerse,
                    RawSourceExcerpt = dto.RawSourceExcerpt,
                    Source = dto.Source,
                    Embedding = embedding,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow,
                });
                results.Add(new { id = dto.Id, status = "inserted" });
            }
            else
            {
                existing.SignatureType = dto.SignatureType;
                existing.Signatures = dto.Signatures.Select(s => s.Trim().ToLowerInvariant()).Distinct().ToList();
                existing.Title = dto.Title;
                existing.Content = dto.Content;
                existing.Themes = dto.Themes ?? [];
                existing.Polarity = string.IsNullOrWhiteSpace(dto.Polarity) ? "mixed" : dto.Polarity;
                existing.Scope = string.IsNullOrWhiteSpace(dto.Scope) ? "lifetime" : dto.Scope;
                existing.SourceBook = dto.SourceBook;
                existing.SourceAuthor = dto.SourceAuthor;
                existing.SourceYear = dto.SourceYear;
                existing.SourceLicense = dto.SourceLicense;
                existing.SourceChapter = dto.SourceChapter;
                existing.SourceVerse = dto.SourceVerse;
                existing.RawSourceExcerpt = dto.RawSourceExcerpt;
                existing.Source = dto.Source;
                existing.Embedding = embedding;
                existing.UpdatedAt = DateTime.UtcNow;
                results.Add(new { id = dto.Id, status = "updated" });
            }
        }

        await db.SaveChangesAsync(ct);
        return Ok(new { count = dtos.Count, results });
    }

    [HttpGet("count")]
    public async Task<IActionResult> Count(CancellationToken ct)
    {
        var total = await db.Passages.CountAsync(ct);
        var byType = await db.Passages
            .GroupBy(p => p.SignatureType)
            .Select(g => new { type = g.Key, count = g.Count() })
            .OrderBy(x => x.type)
            .ToListAsync(ct);
        return Ok(new { total, byType });
    }

    /// <summary>
    /// Admin-only dump of all passages in ingest DTO shape. Used for retone
    /// passes: pull existing passages, rewrite their content field, re-post
    /// to the batch endpoint (which upserts by id).
    /// Optional signatureType query filters to one type.
    /// </summary>
    [HttpGet("all")]
    public async Task<IActionResult> All(
        [FromQuery] string? signatureType,
        CancellationToken ct)
    {
        var q = db.Passages.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(signatureType))
            q = q.Where(p => p.SignatureType == signatureType);

        var passages = await q
            .OrderBy(p => p.SignatureType)
            .ThenBy(p => p.PassageId)
            .Select(p => new
            {
                id = p.PassageId,
                signatureType = p.SignatureType,
                signatures = p.Signatures,
                title = p.Title,
                content = p.Content,
                themes = p.Themes,
                polarity = p.Polarity,
                scope = p.Scope,
                sourceBook = p.SourceBook,
                sourceAuthor = p.SourceAuthor,
                sourceYear = p.SourceYear,
                sourceLicense = p.SourceLicense,
                sourceChapter = p.SourceChapter,
                sourceVerse = p.SourceVerse,
                rawSourceExcerpt = p.RawSourceExcerpt,
                source = p.Source,
            })
            .ToListAsync(ct);

        return Ok(passages);
    }

    private static bool Validate(IngestPassageDto dto, out string error)
    {
        if (string.IsNullOrWhiteSpace(dto.Id)) { error = "id required"; return false; }
        if (string.IsNullOrWhiteSpace(dto.Content)) { error = "content required"; return false; }
        if (string.IsNullOrWhiteSpace(dto.SourceBook)) { error = "sourceBook required"; return false; }
        if (string.IsNullOrWhiteSpace(dto.SourceAuthor)) { error = "sourceAuthor required"; return false; }
        if (dto.SourceYear <= 0) { error = "sourceYear required"; return false; }
        if (string.IsNullOrWhiteSpace(dto.SourceLicense)) { error = "sourceLicense required"; return false; }
        if (dto.Signatures is null || dto.Signatures.Count == 0) { error = "signatures required"; return false; }
        error = string.Empty;
        return true;
    }

    private static string BuildEmbeddingText(IngestPassageDto dto)
        => $"{dto.Title}\n{dto.Content}\n{string.Join(" ", dto.Themes ?? [])}";
}
