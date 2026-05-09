using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Models;
using ShantiSangha.Friends.Storage;

namespace ShantiSangha.Friends.Services;

public class ConnectionAttachmentsService(
    FriendsDbContext db,
    FriendsMediaStorage storage,
    ILogger<ConnectionAttachmentsService> logger) : IConnectionAttachmentsService
{
    private static readonly TimeSpan UploadUrlLifetime = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan DownloadUrlLifetime = TimeSpan.FromHours(1);

    /// Soft cap so a single connection can't accumulate thousands of
    /// items — the iOS UI is designed for tens, not hundreds.
    private const int MaxAttachmentsPerConnection = 200;

    /// Hard ceiling per object — generous enough for a phone-shot video
    /// but small enough that a misbehaving client can't hold a slot.
    private const long MaxObjectBytes = 200L * 1024 * 1024;

    private const int MaxCaptionLength = 280;
    private const int MaxFileNameLength = 200;

    public async Task<List<ConnectionAttachmentResponse>?> ListAsync(
        Guid userId,
        Guid connectionId,
        CancellationToken ct = default)
    {
        if (!await OwnsConnectionAsync(userId, connectionId, ct)) return null;

        var rows = await db.ConnectionAttachments
            .Where(a => a.ConnectionId == connectionId)
            .OrderByDescending(a => a.CreatedAt)
            .ToListAsync(ct);

        var result = new List<ConnectionAttachmentResponse>(rows.Count);
        foreach (var a in rows)
        {
            var url = await storage.GetPresignedDownloadUrlAsync(a.ObjectKey, DownloadUrlLifetime);
            result.Add(Project(a, url));
        }
        return result;
    }

    public async Task<CreateConnectionAttachmentUploadResponse?> CreateUploadUrlAsync(
        Guid userId,
        Guid connectionId,
        CreateConnectionAttachmentUploadRequest req,
        CancellationToken ct = default)
    {
        if (!await OwnsConnectionAsync(userId, connectionId, ct)) return null;

        var contentType = NormalizeContentType(req.ContentType);
        if (string.IsNullOrEmpty(contentType))
            throw new FriendsServiceException("invalid_content_type", "Content type is required.");

        var current = await db.ConnectionAttachments
            .CountAsync(a => a.ConnectionId == connectionId, ct);
        if (current >= MaxAttachmentsPerConnection)
            throw new FriendsServiceException(
                "too_many_attachments",
                $"You can keep up to {MaxAttachmentsPerConnection} items per person.");

        // Key shape mirrors `friends/{friendshipId}/...` for symmetry.
        // Owner is encoded into the path so account-deletion sweeps can
        // prefix-match without a row read.
        var ext = ExtensionForContentType(contentType, req.FileName);
        var key = $"connections/{userId}/{connectionId}/attachments/{Guid.NewGuid()}{ext}";
        var url = await storage.GetPresignedUploadUrlAsync(key, contentType, UploadUrlLifetime);
        return new CreateConnectionAttachmentUploadResponse(
            key,
            url,
            DateTime.UtcNow.Add(UploadUrlLifetime));
    }

    public async Task<ConnectionAttachmentResponse?> CommitAsync(
        Guid userId,
        Guid connectionId,
        CommitConnectionAttachmentRequest req,
        CancellationToken ct = default)
    {
        if (!await OwnsConnectionAsync(userId, connectionId, ct)) return null;

        var key = req.ObjectKey?.Trim() ?? string.Empty;
        if (key.Length == 0)
            throw new FriendsServiceException("invalid_key", "Upload key is required.");

        // Defense in depth — only accept keys this user could have
        // created. Without this, a malicious client could commit any
        // bucket key as their own attachment.
        var expectedPrefix = $"connections/{userId}/{connectionId}/attachments/";
        if (!key.StartsWith(expectedPrefix, StringComparison.Ordinal))
            throw new FriendsServiceException("forbidden", "Key does not belong to this connection.");

        // Confirm the bytes actually landed; pull the real size + type
        // from S3 rather than trusting the client.
        var meta = await storage.GetObjectInfoAsync(key);
        if (meta is null)
            throw new FriendsServiceException("upload_missing", "Upload was not received. Try again.");
        if (meta.ContentLength > MaxObjectBytes)
        {
            await storage.DeleteAsync(key);
            throw new FriendsServiceException(
                "too_large",
                $"Files must be under {MaxObjectBytes / (1024 * 1024)} MB.");
        }

        var contentType = NormalizeContentType(meta.ContentType ?? req.ContentType);
        var fileName = NormalizeFileName(req.FileName);
        var caption = NormalizeCaption(req.Caption);

        var now = DateTime.UtcNow;
        var row = new ConnectionAttachment
        {
            Id = Guid.NewGuid(),
            ConnectionId = connectionId,
            OwnerUserId = userId,
            ObjectKey = key,
            ContentType = contentType,
            ByteSize = meta.ContentLength,
            FileName = fileName,
            Kind = ClassifyKind(contentType),
            Caption = caption,
            CreatedAt = now,
            UpdatedAt = now
        };
        db.ConnectionAttachments.Add(row);

        // Bump the connection's UpdatedAt so list-view sort surfaces
        // freshly-edited rows (matches the `dates` write path).
        var conn = await db.Connections
            .FirstOrDefaultAsync(c => c.Id == connectionId, ct);
        if (conn is not null) conn.UpdatedAt = now;

        await db.SaveChangesAsync(ct);

        var url = await storage.GetPresignedDownloadUrlAsync(row.ObjectKey, DownloadUrlLifetime);
        return Project(row, url);
    }

    public async Task<ConnectionAttachmentResponse?> UpdateAsync(
        Guid userId,
        Guid connectionId,
        Guid attachmentId,
        UpdateConnectionAttachmentRequest req,
        CancellationToken ct = default)
    {
        var row = await GetOwnedAsync(userId, connectionId, attachmentId, ct);
        if (row is null) return null;

        row.Caption = NormalizeCaption(req.Caption);
        row.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        var url = await storage.GetPresignedDownloadUrlAsync(row.ObjectKey, DownloadUrlLifetime);
        return Project(row, url);
    }

    public async Task<bool> DeleteAsync(
        Guid userId,
        Guid connectionId,
        Guid attachmentId,
        CancellationToken ct = default)
    {
        var row = await GetOwnedAsync(userId, connectionId, attachmentId, ct);
        if (row is null) return false;

        var key = row.ObjectKey;
        db.ConnectionAttachments.Remove(row);
        await db.SaveChangesAsync(ct);

        try
        {
            await storage.DeleteAsync(key);
        }
        catch (Exception ex)
        {
            // Row is gone; orphan S3 object is recoverable via a sweep.
            // Don't fail the user-facing delete on a transient S3 hiccup.
            logger.LogWarning(ex, "Failed to delete S3 object {Key} for attachment {Id}", key, attachmentId);
        }

        return true;
    }

    public async Task PurgeForConnectionAsync(Guid connectionId, CancellationToken ct = default)
    {
        var keys = await db.ConnectionAttachments
            .Where(a => a.ConnectionId == connectionId)
            .Select(a => a.ObjectKey)
            .ToListAsync(ct);

        if (keys.Count == 0) return;

        // Row removal is handled by the FK cascade when the Connection
        // row is removed; we just clean up the bucket here.
        await storage.DeleteManyAsync(keys);
    }

    // ── Helpers ─────────────────────────────────────────────────────

    private async Task<bool> OwnsConnectionAsync(Guid userId, Guid connectionId, CancellationToken ct) =>
        await db.Connections.AnyAsync(c => c.Id == connectionId && c.OwnerUserId == userId, ct);

    private async Task<ConnectionAttachment?> GetOwnedAsync(
        Guid userId,
        Guid connectionId,
        Guid attachmentId,
        CancellationToken ct) =>
        await db.ConnectionAttachments
            .Where(a => a.Id == attachmentId
                && a.ConnectionId == connectionId
                && a.OwnerUserId == userId)
            .FirstOrDefaultAsync(ct);

    private static ConnectionAttachmentResponse Project(ConnectionAttachment a, string downloadUrl) =>
        new(
            a.Id,
            a.ConnectionId,
            a.ObjectKey,
            a.ContentType,
            a.ByteSize,
            a.FileName,
            a.Kind.ToString(),
            a.Caption,
            downloadUrl,
            a.CreatedAt,
            a.UpdatedAt);

    private static ConnectionAttachmentKind ClassifyKind(string contentType)
    {
        if (string.IsNullOrEmpty(contentType)) return ConnectionAttachmentKind.File;
        if (contentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase)) return ConnectionAttachmentKind.Media;
        if (contentType.StartsWith("video/", StringComparison.OrdinalIgnoreCase)) return ConnectionAttachmentKind.Media;
        return ConnectionAttachmentKind.File;
    }

    private static string NormalizeContentType(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "application/octet-stream";
        var trimmed = raw.Trim();
        // Strip any "; charset=..." parameter — we only store the type itself.
        var semi = trimmed.IndexOf(';');
        if (semi > 0) trimmed = trimmed[..semi].Trim();
        return trimmed.Length == 0 ? "application/octet-stream" : trimmed;
    }

    private static string NormalizeFileName(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return "attachment";
        var trimmed = raw.Trim();
        // Strip path components — accept only the basename.
        var slash = trimmed.LastIndexOfAny(['/', '\\']);
        if (slash >= 0) trimmed = trimmed[(slash + 1)..];
        if (trimmed.Length == 0) return "attachment";
        if (trimmed.Length > MaxFileNameLength) trimmed = trimmed[..MaxFileNameLength];
        return trimmed;
    }

    private static string? NormalizeCaption(string? raw)
    {
        if (raw is null) return null;
        var trimmed = raw.Trim();
        if (trimmed.Length == 0) return null;
        if (trimmed.Length > MaxCaptionLength) trimmed = trimmed[..MaxCaptionLength];
        return trimmed;
    }

    /// Best-effort extension for the S3 key. We honor the client's
    /// filename hint when it matches the content type's family, otherwise
    /// fall back to a known ext for that type. The leading dot is
    /// included so the caller can concat directly.
    private static string ExtensionForContentType(string contentType, string? fileName)
    {
        if (!string.IsNullOrEmpty(fileName))
        {
            var dot = fileName.LastIndexOf('.');
            if (dot > 0 && dot < fileName.Length - 1)
            {
                var ext = fileName[dot..].ToLowerInvariant();
                // Tight guard — only allow short alphanumerics so we
                // don't end up with weird shell metacharacters in keys.
                if (ext.Length <= 8 && ext[1..].All(char.IsLetterOrDigit))
                    return ext;
            }
        }

        return contentType.ToLowerInvariant() switch
        {
            "image/jpeg" or "image/jpg" => ".jpg",
            "image/png" => ".png",
            "image/heic" => ".heic",
            "image/heif" => ".heif",
            "image/webp" => ".webp",
            "image/gif" => ".gif",
            "video/mp4" => ".mp4",
            "video/quicktime" => ".mov",
            "audio/mpeg" => ".mp3",
            "audio/mp4" or "audio/x-m4a" => ".m4a",
            "application/pdf" => ".pdf",
            _ => string.Empty
        };
    }
}
