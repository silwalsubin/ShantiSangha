using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Models;
using ShantiSangha.Friends.Storage;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

public class ConnectionsService(
    FriendsDbContext db,
    IFriendsService friends,
    IProfileQueryService profileQuery,
    IConnectionAttachmentsService attachments,
    FriendsMediaStorage storage,
    ILogger<ConnectionsService> logger) : IConnectionsService
{
    private static readonly TimeSpan AvatarUploadUrlLifetime = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan AvatarDownloadUrlLifetime = TimeSpan.FromHours(1);

    private static readonly HashSet<string> AllowedAvatarContentTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/heic",
        "image/heif",
        "image/webp"
    };

    public async Task<List<ConnectionResponse>> ListAsync(Guid userId, CancellationToken ct = default)
    {
        var rows = await db.Connections
            .Where(c => c.OwnerUserId == userId)
            .Join(db.Persons, c => c.PersonId, p => p.Id, (c, p) => new { Conn = c, Person = p })
            .OrderByDescending(x => x.Conn.UpdatedAt)
            .ToListAsync(ct);

        if (rows.Count == 0) return [];

        // Bulk-fetch last-message + unread counts ONLY for the paired
        // subset — local connections never carry these fields.
        var friendshipIds = rows
            .Where(x => x.Conn.FriendshipId.HasValue)
            .Select(x => x.Conn.FriendshipId!.Value)
            .ToList();

        var lastByFs = friendshipIds.Count == 0
            ? new Dictionary<Guid, FriendMessage>()
            : (await db.Messages
                .Where(m => friendshipIds.Contains(m.FriendshipId))
                .GroupBy(m => m.FriendshipId)
                .Select(g => g.OrderByDescending(m => m.SentAt).First())
                .ToListAsync(ct))
                .ToDictionary(m => m.FriendshipId, m => m);

        var unreadByFs = friendshipIds.Count == 0
            ? new Dictionary<Guid, int>()
            : (await db.Messages
                .Where(m => friendshipIds.Contains(m.FriendshipId)
                    && m.SenderUserId != userId
                    && m.ReadAt == null)
                .GroupBy(m => m.FriendshipId)
                .Select(g => new { FriendshipId = g.Key, Count = g.Count() })
                .ToListAsync(ct))
                .ToDictionary(x => x.FriendshipId, x => x.Count);

        var result = new List<ConnectionResponse>(rows.Count);
        foreach (var x in rows)
        {
            var (preview, sentAt, unread) = (string.Empty as string, default(DateTime?), 0);
            string? lastImageKey = null;
            if (x.Conn.FriendshipId is { } fsId)
            {
                if (lastByFs.TryGetValue(fsId, out var last))
                {
                    preview = BuildPreview(last);
                    sentAt = last.SentAt;
                    if (last.Kind == FriendMessageKind.Image) lastImageKey = last.StorageKey;
                }
                unreadByFs.TryGetValue(fsId, out unread);
            }
            result.Add(await ProjectAsync(x.Conn, x.Person, preview, sentAt, unread, ct, lastImageKey));
        }
        return result;
    }

    public async Task<ConnectionResponse?> GetAsync(Guid userId, Guid connectionId, CancellationToken ct = default)
    {
        var hit = await db.Connections
            .Where(c => c.Id == connectionId && c.OwnerUserId == userId)
            .Join(db.Persons, c => c.PersonId, p => p.Id, (c, p) => new { Conn = c, Person = p })
            .FirstOrDefaultAsync(ct);
        if (hit is null) return null;

        string? preview = null;
        DateTime? sentAt = null;
        int unread = 0;
        string? lastImageKey = null;
        if (hit.Conn.FriendshipId is { } fsId)
        {
            var last = await db.Messages
                .Where(m => m.FriendshipId == fsId)
                .OrderByDescending(m => m.SentAt)
                .FirstOrDefaultAsync(ct);
            if (last is not null)
            {
                preview = BuildPreview(last);
                sentAt = last.SentAt;
                if (last.Kind == FriendMessageKind.Image) lastImageKey = last.StorageKey;
            }
            unread = await db.Messages.CountAsync(
                m => m.FriendshipId == fsId && m.SenderUserId != userId && m.ReadAt == null, ct);
        }
        return await ProjectAsync(hit.Conn, hit.Person, preview, sentAt, unread, ct, lastImageKey);
    }

    public async Task<ConnectionResponse> CreateLocalAsync(
        Guid userId,
        CreateConnectionRequest req,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var person = new Person
        {
            Id = Guid.NewGuid(),
            UserId = null,
            DisplayName = (req.DisplayName ?? string.Empty).Trim(),
            PhoneNumber = NullIfEmpty(req.PhoneNumber),
            Email = NullIfEmpty(req.Email),
            Country = NullIfEmpty(req.Country),
            State = NullIfEmpty(req.State),
            City = NullIfEmpty(req.City),
            Address = NullIfEmpty(req.Address),
            CreatedAt = now,
            UpdatedAt = now
        };
        if (string.IsNullOrWhiteSpace(person.DisplayName))
            throw new FriendsServiceException("display_name_required", "A name is required.");

        var conn = new Connection
        {
            Id = Guid.NewGuid(),
            OwnerUserId = userId,
            PersonId = person.Id,
            Circles = NormalizeCircles(req.Circles),
            Nickname = NullIfEmpty(req.Nickname)?.Trim(),
            PrivateNotes = string.IsNullOrEmpty(req.PrivateNotes) ? null : req.PrivateNotes,
            FriendshipId = null,
            CreatedAt = now,
            UpdatedAt = now
        };

        db.Persons.Add(person);
        db.Connections.Add(conn);
        await db.SaveChangesAsync(ct);

        return await ProjectAsync(conn, person, null, null, 0, ct);
    }

    public async Task<ConnectionResponse?> UpdateAsync(
        Guid userId,
        Guid connectionId,
        UpdateConnectionRequest req,
        CancellationToken ct = default)
    {
        var conn = await db.Connections
            .FirstOrDefaultAsync(c => c.Id == connectionId && c.OwnerUserId == userId, ct);
        if (conn is null) return null;

        // null = leave alone, [] = clear, otherwise replace with the
        // normalized set. Treating [] explicitly as "clear" keeps the
        // contract symmetric with the iOS chip-input UX.
        if (req.Circles is not null)
        {
            conn.Circles = NormalizeCircles(req.Circles);
        }

        if (req.ClearNickname == true) conn.Nickname = null;
        else if (req.Nickname is not null)
        {
            var trimmed = req.Nickname.Trim();
            conn.Nickname = trimmed.Length == 0 ? null : trimmed;
        }

        if (req.ClearPrivateNotes == true) conn.PrivateNotes = null;
        else if (req.PrivateNotes is not null)
        {
            conn.PrivateNotes = string.IsNullOrEmpty(req.PrivateNotes) ? null : req.PrivateNotes;
        }

        // Avatar swap. Defense in depth: only accept keys that the
        // dedicated upload-url endpoint could have produced for this
        // (owner, connection) pair. When the key changes, fire-and-forget
        // delete the previous S3 object so we don't accumulate orphans.
        var previousAvatarKey = conn.PrivateAvatarKey;
        if (req.ClearPrivateAvatar == true)
        {
            conn.PrivateAvatarKey = null;
        }
        else if (req.PrivateAvatarKey is not null)
        {
            var trimmedKey = req.PrivateAvatarKey.Trim();
            if (trimmedKey.Length == 0)
            {
                conn.PrivateAvatarKey = null;
            }
            else
            {
                var expectedPrefix = $"connections/{userId}/{connectionId}/avatar/";
                if (!trimmedKey.StartsWith(expectedPrefix, StringComparison.Ordinal))
                {
                    throw new FriendsServiceException(
                        "forbidden",
                        "Avatar key does not belong to this connection.");
                }
                conn.PrivateAvatarKey = trimmedKey;
            }
        }

        if (!string.IsNullOrWhiteSpace(previousAvatarKey)
            && previousAvatarKey != conn.PrivateAvatarKey)
        {
            _ = SafeDeleteAvatarAsync(previousAvatarKey);
        }

        conn.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        return await GetAsync(userId, connectionId, ct);
    }

    public async Task<PersonResponse?> UpdatePersonAsync(
        Guid userId,
        Guid connectionId,
        UpdatePersonRequest req,
        CancellationToken ct = default)
    {
        var hit = await db.Connections
            .Where(c => c.Id == connectionId && c.OwnerUserId == userId)
            .Join(db.Persons, c => c.PersonId, p => p.Id, (c, p) => new { Conn = c, Person = p })
            .FirstOrDefaultAsync(ct);
        if (hit is null) return null;

        var person = hit.Person;
        // Permission gate: callable iff Person is local (owned by this
        // Connection's owner) OR Person represents the caller themselves.
        var isLocalAndMine = person.UserId is null;
        var isMyOwnPerson = person.UserId == userId;
        if (!isLocalAndMine && !isMyOwnPerson)
        {
            throw new FriendsServiceException("forbidden",
                "You can't edit another user's profile from your circle.");
        }

        if (req.DisplayName is not null)
        {
            var trimmed = req.DisplayName.Trim();
            if (trimmed.Length == 0)
                throw new FriendsServiceException("display_name_required", "A name is required.");
            person.DisplayName = trimmed;
        }

        if (req.ClearPhoneNumber == true) person.PhoneNumber = null;
        else if (req.PhoneNumber is not null) person.PhoneNumber = NullIfEmpty(req.PhoneNumber);

        if (req.ClearEmail == true) person.Email = null;
        else if (req.Email is not null) person.Email = NullIfEmpty(req.Email);

        if (req.ClearCountry == true) person.Country = null;
        else if (req.Country is not null) person.Country = NullIfEmpty(req.Country);

        if (req.ClearState == true) person.State = null;
        else if (req.State is not null) person.State = NullIfEmpty(req.State);

        if (req.ClearCity == true) person.City = null;
        else if (req.City is not null) person.City = NullIfEmpty(req.City);

        if (req.ClearAddress == true) person.Address = null;
        else if (req.Address is not null) person.Address = NullIfEmpty(req.Address);

        person.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        return await BuildPersonResponseAsync(person, ct);
    }

    public async Task<bool> DeleteAsync(Guid userId, Guid connectionId, CancellationToken ct = default)
    {
        var conn = await db.Connections
            .FirstOrDefaultAsync(c => c.Id == connectionId && c.OwnerUserId == userId, ct);
        if (conn is null) return false;

        // Sweep S3 keepsakes BEFORE the row cascade fires — once the
        // Connections rows are gone, we'd have nothing to read the
        // ObjectKeys from. For paired connections, both sides'
        // attachments and private avatars need to be purged because
        // EndFriendshipAsync removes both Connection rows.
        if (conn.FriendshipId is { } fsId)
        {
            var paired = await db.Connections
                .Where(c => c.FriendshipId == fsId)
                .Select(c => new { c.Id, c.PrivateAvatarKey })
                .ToListAsync(ct);
            foreach (var p in paired)
            {
                await attachments.PurgeForConnectionAsync(p.Id, ct);
                if (!string.IsNullOrWhiteSpace(p.PrivateAvatarKey))
                {
                    _ = SafeDeleteAvatarAsync(p.PrivateAvatarKey);
                }
            }
            // Paired: end the friendship — that path also removes both
            // Connection rows, which cascade-deletes the now-empty
            // ConnectionAttachments rows via FK.
            await friends.EndFriendshipAsync(userId, fsId, ct);
            return true;
        }

        await attachments.PurgeForConnectionAsync(connectionId, ct);
        if (!string.IsNullOrWhiteSpace(conn.PrivateAvatarKey))
        {
            _ = SafeDeleteAvatarAsync(conn.PrivateAvatarKey);
        }

        // Local: removing the Connection cascades to the Person via
        // ON DELETE CASCADE.
        db.Connections.Remove(conn);
        await db.SaveChangesAsync(ct);
        return true;
    }

    // ── Helpers ─────────────────────────────────────────────────────

    private async Task<ConnectionResponse> ProjectAsync(
        Connection conn,
        Person person,
        string? preview,
        DateTime? sentAt,
        int unread,
        CancellationToken ct,
        string? lastImageKey = null)
    {
        var personDto = await BuildPersonResponseAsync(person, ct);

        // Fresh presigned GET URL on every read; never persist the URL
        // because S3 expires it. Failures are non-fatal — the iOS layer
        // will fall back to the linked Person avatar or initials.
        string? privateAvatarUrl = null;
        if (!string.IsNullOrWhiteSpace(conn.PrivateAvatarKey))
        {
            try
            {
                privateAvatarUrl = await storage.GetPresignedDownloadUrlAsync(
                    conn.PrivateAvatarKey,
                    AvatarDownloadUrlLifetime);
            }
            catch (Exception ex)
            {
                logger.LogWarning(
                    ex,
                    "Failed to presign private avatar for connection {ConnectionId}",
                    conn.Id);
            }
        }

        // Presign the last image (when the most recent message is a
        // photo) so the chat list can show a thumbnail. Same lifetime and
        // best-effort handling as the avatar above.
        string? lastMessageImageUrl = null;
        if (!string.IsNullOrWhiteSpace(lastImageKey))
        {
            try
            {
                lastMessageImageUrl = await storage.GetPresignedDownloadUrlAsync(
                    lastImageKey,
                    AvatarDownloadUrlLifetime);
            }
            catch (Exception ex)
            {
                logger.LogWarning(
                    ex,
                    "Failed to presign last-message image for connection {ConnectionId}",
                    conn.Id);
            }
        }

        return new ConnectionResponse(
            conn.Id,
            conn.OwnerUserId,
            conn.PersonId,
            conn.Circles ?? [],
            conn.Nickname,
            conn.PrivateNotes,
            conn.FriendshipId,
            Messageable: person.UserId.HasValue && conn.FriendshipId.HasValue,
            conn.CreatedAt,
            conn.UpdatedAt,
            personDto,
            preview,
            sentAt,
            unread,
            privateAvatarUrl,
            lastMessageImageUrl);
    }

    public async Task<CreateConnectionAvatarUploadResponse?> CreateAvatarUploadUrlAsync(
        Guid userId,
        Guid connectionId,
        CreateConnectionAvatarUploadRequest req,
        CancellationToken ct = default)
    {
        var owns = await db.Connections
            .AnyAsync(c => c.Id == connectionId && c.OwnerUserId == userId, ct);
        if (!owns) return null;

        var contentType = (req.ContentType ?? string.Empty).Trim();
        if (!AllowedAvatarContentTypes.Contains(contentType))
        {
            throw new FriendsServiceException(
                "unsupported_type",
                "Avatar must be a JPEG, PNG, HEIC, or WebP image.");
        }

        var ext = ExtensionForAvatarContentType(contentType);
        var key = $"connections/{userId}/{connectionId}/avatar/{Guid.NewGuid()}{ext}";
        var url = await storage.GetPresignedUploadUrlAsync(key, contentType, AvatarUploadUrlLifetime);
        return new CreateConnectionAvatarUploadResponse(
            key,
            url,
            DateTime.UtcNow.Add(AvatarUploadUrlLifetime));
    }

    private async Task SafeDeleteAvatarAsync(string key)
    {
        try
        {
            await storage.DeleteAsync(key);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to delete superseded private avatar {Key}", key);
        }
    }

    private static string ExtensionForAvatarContentType(string contentType) =>
        contentType.ToLowerInvariant() switch
        {
            "image/jpeg" or "image/jpg" => ".jpg",
            "image/png" => ".png",
            "image/heic" => ".heic",
            "image/heif" => ".heif",
            "image/webp" => ".webp",
            _ => string.Empty
        };

    /// For a linked Person we read display name + biographical data
    /// directly from `Identity.Profile` so the row stays in sync with
    /// the user's own profile edits. For a local Person we trust the
    /// row's own columns. AvatarKey/AvatarUrl always come from
    /// `IProfileQueryService` (only meaningful for linked).
    private async Task<PersonResponse> BuildPersonResponseAsync(Person p, CancellationToken ct)
    {
        if (p.UserId is { } uid)
        {
            var displayName = await profileQuery.GetDisplayNameAsync(uid, ct) ?? p.DisplayName;
            var avatar = await profileQuery.GetAvatarInfoAsync(uid, ct);
            var location = await profileQuery.GetLocationAsync(uid, ct);
            return new PersonResponse(
                p.Id,
                p.UserId,
                displayName,
                p.PhoneNumber,
                p.Email,
                location.Country,
                location.State,
                location.City,
                p.Address,
                avatar.AvatarKey,
                avatar.AvatarUrl);
        }

        return new PersonResponse(
            p.Id,
            null,
            p.DisplayName,
            p.PhoneNumber,
            p.Email,
            p.Country,
            p.State,
            p.City,
            p.Address,
            // Local persons have no avatar — iOS falls back to initials.
            null,
            null);
    }

    /// Trim, drop empties, dedupe case-insensitively (keep first-seen casing
    /// so "Family" wins over "family"), cap label length at 64 chars and
    /// the array at 16 entries — both are sanity bounds rather than product
    /// rules; raise them later if the UX wants more headroom.
    private static string[] NormalizeCircles(IReadOnlyList<string>? raw)
    {
        if (raw is null || raw.Count == 0) return [];

        const int MaxCircles = 16;
        const int MaxLabelLength = 64;

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<string>(Math.Min(raw.Count, MaxCircles));

        foreach (var item in raw)
        {
            if (item is null) continue;
            var trimmed = item.Trim();
            if (trimmed.Length == 0) continue;
            if (trimmed.Length > MaxLabelLength) trimmed = trimmed[..MaxLabelLength];
            if (seen.Add(trimmed))
            {
                result.Add(trimmed);
                if (result.Count >= MaxCircles) break;
            }
        }

        return result.ToArray();
    }

    private static string? NullIfEmpty(string? s) =>
        string.IsNullOrWhiteSpace(s) ? null : s;

    private static string BuildPreview(FriendMessage m) => m.Kind switch
    {
        FriendMessageKind.Text => string.IsNullOrWhiteSpace(m.Body)
            ? "(empty message)"
            : (m.Body.Length > 80 ? m.Body[..80] + "…" : m.Body),
        FriendMessageKind.Image => "(photo)",
        FriendMessageKind.Voice => "(voice message)",
        _ => "(message)"
    };
}
