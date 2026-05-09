using Microsoft.EntityFrameworkCore;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

public class ConnectionsService(
    FriendsDbContext db,
    IFriendsService friends,
    IProfileQueryService profileQuery) : IConnectionsService
{
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

        // Bulk-load important dates for all connections in one round trip
        // so the per-row projection doesn't N+1. Sorted ascending so the
        // iOS list reads in chronological order without re-sorting.
        var connIds = rows.Select(x => x.Conn.Id).ToList();
        var datesByConn = (await db.ConnectionDates
                .Where(d => connIds.Contains(d.ConnectionId))
                .OrderBy(d => d.Date)
                .ToListAsync(ct))
            .GroupBy(d => d.ConnectionId)
            .ToDictionary(g => g.Key, g => (IReadOnlyList<ConnectionDate>)g.ToList());

        var result = new List<ConnectionResponse>(rows.Count);
        foreach (var x in rows)
        {
            var (preview, sentAt, unread) = (string.Empty as string, default(DateTime?), 0);
            if (x.Conn.FriendshipId is { } fsId)
            {
                if (lastByFs.TryGetValue(fsId, out var last))
                {
                    preview = BuildPreview(last);
                    sentAt = last.SentAt;
                }
                unreadByFs.TryGetValue(fsId, out unread);
            }
            var dates = datesByConn.TryGetValue(x.Conn.Id, out var d) ? d : [];
            result.Add(await ProjectAsync(x.Conn, x.Person, dates, preview, sentAt, unread, ct));
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
        if (hit.Conn.FriendshipId is { } fsId)
        {
            var last = await db.Messages
                .Where(m => m.FriendshipId == fsId)
                .OrderByDescending(m => m.SentAt)
                .FirstOrDefaultAsync(ct);
            if (last is not null) { preview = BuildPreview(last); sentAt = last.SentAt; }
            unread = await db.Messages.CountAsync(
                m => m.FriendshipId == fsId && m.SenderUserId != userId && m.ReadAt == null, ct);
        }
        var dates = await LoadDatesAsync(hit.Conn.Id, ct);
        return await ProjectAsync(hit.Conn, hit.Person, dates, preview, sentAt, unread, ct);
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

        return await ProjectAsync(conn, person, [], null, null, 0, ct);
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

        if (conn.FriendshipId is { } fsId)
        {
            // Paired: end the friendship — that path also removes both
            // Connection rows because it cascades to the FK.
            await friends.EndFriendshipAsync(userId, fsId, ct);
            return true;
        }

        // Local: removing the Connection cascades to the Person via
        // ON DELETE CASCADE.
        db.Connections.Remove(conn);
        await db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<ConnectionDateResponse?> AddDateAsync(
        Guid userId,
        Guid connectionId,
        AddConnectionDateRequest req,
        CancellationToken ct = default)
    {
        var conn = await db.Connections
            .FirstOrDefaultAsync(c => c.Id == connectionId && c.OwnerUserId == userId, ct);
        if (conn is null) return null;

        var label = NormalizeDateLabel(req.Label)
            ?? throw new FriendsServiceException("label_required", "A label is required.");

        // Soft cap so a single connection can't accumulate hundreds of
        // dates — the iOS list isn't designed for that and there's no
        // product reason to allow it.
        const int MaxDates = 32;
        var current = await db.ConnectionDates.CountAsync(d => d.ConnectionId == connectionId, ct);
        if (current >= MaxDates)
            throw new FriendsServiceException("too_many_dates",
                $"You can keep up to {MaxDates} dates per person.");

        var now = DateTime.UtcNow;
        var entry = new ConnectionDate
        {
            Id = Guid.NewGuid(),
            ConnectionId = connectionId,
            Label = label,
            Date = req.Date,
            Recurrence = req.Recurrence,
            CreatedAt = now,
            UpdatedAt = now
        };
        db.ConnectionDates.Add(entry);

        // Bump Connection.UpdatedAt so the list view re-orders to surface
        // the freshly-edited row at the top.
        conn.UpdatedAt = now;
        await db.SaveChangesAsync(ct);

        return new ConnectionDateResponse(entry.Id, entry.Label, entry.Date, entry.Recurrence);
    }

    public async Task<ConnectionDateResponse?> UpdateDateAsync(
        Guid userId,
        Guid connectionId,
        Guid dateId,
        UpdateConnectionDateRequest req,
        CancellationToken ct = default)
    {
        var hit = await db.ConnectionDates
            .Where(d => d.Id == dateId && d.ConnectionId == connectionId)
            .Join(db.Connections,
                  d => d.ConnectionId,
                  c => c.Id,
                  (d, c) => new { Date = d, Conn = c })
            .FirstOrDefaultAsync(d => d.Conn.OwnerUserId == userId, ct);
        if (hit is null) return null;

        var label = NormalizeDateLabel(req.Label)
            ?? throw new FriendsServiceException("label_required", "A label is required.");

        var now = DateTime.UtcNow;
        hit.Date.Label = label;
        hit.Date.Date = req.Date;
        hit.Date.Recurrence = req.Recurrence;
        hit.Date.UpdatedAt = now;
        hit.Conn.UpdatedAt = now;
        await db.SaveChangesAsync(ct);

        return new ConnectionDateResponse(hit.Date.Id, hit.Date.Label, hit.Date.Date, hit.Date.Recurrence);
    }

    public async Task<bool> DeleteDateAsync(
        Guid userId,
        Guid connectionId,
        Guid dateId,
        CancellationToken ct = default)
    {
        var hit = await db.ConnectionDates
            .Where(d => d.Id == dateId && d.ConnectionId == connectionId)
            .Join(db.Connections,
                  d => d.ConnectionId,
                  c => c.Id,
                  (d, c) => new { Date = d, Conn = c })
            .FirstOrDefaultAsync(d => d.Conn.OwnerUserId == userId, ct);
        if (hit is null) return false;

        db.ConnectionDates.Remove(hit.Date);
        hit.Conn.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    // ── Helpers ─────────────────────────────────────────────────────

    private async Task<ConnectionResponse> ProjectAsync(
        Connection conn,
        Person person,
        IReadOnlyList<ConnectionDate> dates,
        string? preview,
        DateTime? sentAt,
        int unread,
        CancellationToken ct)
    {
        var personDto = await BuildPersonResponseAsync(person, ct);
        var dateDtos = dates
            .Select(d => new ConnectionDateResponse(d.Id, d.Label, d.Date, d.Recurrence))
            .ToList();
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
            dateDtos,
            preview,
            sentAt,
            unread);
    }

    private async Task<IReadOnlyList<ConnectionDate>> LoadDatesAsync(
        Guid connectionId,
        CancellationToken ct) =>
        await db.ConnectionDates
            .Where(d => d.ConnectionId == connectionId)
            .OrderBy(d => d.Date)
            .ToListAsync(ct);

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

    /// Trim, collapse to null when empty, cap at 64 chars — the same
    /// label budget Circles use. Returns null when the input is unusable
    /// so callers can throw a clean validation error.
    private static string? NormalizeDateLabel(string? raw)
    {
        if (raw is null) return null;
        var trimmed = raw.Trim();
        if (trimmed.Length == 0) return null;
        if (trimmed.Length > 64) trimmed = trimmed[..64];
        return trimmed;
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
