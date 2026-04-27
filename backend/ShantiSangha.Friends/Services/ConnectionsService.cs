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
            result.Add(await ProjectAsync(x.Conn, x.Person, preview, sentAt, unread, ct));
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
        return await ProjectAsync(hit.Conn, hit.Person, preview, sentAt, unread, ct);
    }

    public async Task<ConnectionResponse> CreateLocalAsync(
        Guid userId,
        CreateConnectionRequest req,
        CancellationToken ct = default)
    {
        ValidateRelationType(req.RelationType, req.CustomRelationLabel);

        var now = DateTime.UtcNow;
        var person = new Person
        {
            Id = Guid.NewGuid(),
            UserId = null,
            DisplayName = (req.DisplayName ?? string.Empty).Trim(),
            BirthDate = req.BirthDate,
            BirthTime = NullIfEmpty(req.BirthTime),
            BirthPlace = NullIfEmpty(req.BirthPlace),
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
            RelationType = ParseRelationType(req.RelationType),
            CustomRelationLabel = NullIfEmpty(req.CustomRelationLabel)?.Trim(),
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

        if (req.RelationType is not null)
        {
            conn.RelationType = ParseRelationType(req.RelationType);
        }

        if (req.ClearCustomRelationLabel == true)
        {
            conn.CustomRelationLabel = null;
        }
        else if (req.CustomRelationLabel is not null)
        {
            conn.CustomRelationLabel = NullIfEmpty(req.CustomRelationLabel)?.Trim();
        }

        // If the type ended up as Other, we need a custom label; if it
        // ended up as anything else, the custom label is meaningless and
        // gets dropped to keep the row consistent.
        if (conn.RelationType == ConnectionType.Other &&
            string.IsNullOrWhiteSpace(conn.CustomRelationLabel))
        {
            throw new FriendsServiceException(
                "custom_relation_label_required",
                "Pick a label for this 'Other' relationship.");
        }
        if (conn.RelationType != ConnectionType.Other)
        {
            conn.CustomRelationLabel = null;
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

        if (req.ClearBirthDate == true) person.BirthDate = null;
        else if (req.BirthDate is not null) person.BirthDate = req.BirthDate;

        if (req.ClearBirthTime == true) person.BirthTime = null;
        else if (req.BirthTime is not null) person.BirthTime = NullIfEmpty(req.BirthTime);

        if (req.ClearBirthPlace == true) person.BirthPlace = null;
        else if (req.BirthPlace is not null) person.BirthPlace = NullIfEmpty(req.BirthPlace);

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

    // ── Helpers ─────────────────────────────────────────────────────

    private async Task<ConnectionResponse> ProjectAsync(
        Connection conn,
        Person person,
        string? preview,
        DateTime? sentAt,
        int unread,
        CancellationToken ct)
    {
        var personDto = await BuildPersonResponseAsync(person, ct);
        return new ConnectionResponse(
            conn.Id,
            conn.OwnerUserId,
            conn.PersonId,
            conn.RelationType.ToString().ToLowerInvariant(),
            conn.CustomRelationLabel,
            conn.Nickname,
            conn.PrivateNotes,
            conn.FriendshipId,
            Messageable: person.UserId.HasValue && conn.FriendshipId.HasValue,
            conn.CreatedAt,
            conn.UpdatedAt,
            personDto,
            preview,
            sentAt,
            unread);
    }

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
            var birth = await profileQuery.GetBirthInfoAsync(uid, ct);
            return new PersonResponse(
                p.Id,
                p.UserId,
                displayName,
                birth.BirthDate,
                birth.BirthTime,
                birth.BirthPlace,
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
            p.BirthDate,
            p.BirthTime,
            p.BirthPlace,
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

    private static void ValidateRelationType(string relationType, string? customLabel)
    {
        var parsed = ParseRelationType(relationType);
        if (parsed == ConnectionType.Other && string.IsNullOrWhiteSpace(customLabel))
        {
            throw new FriendsServiceException(
                "custom_relation_label_required",
                "Pick a label for this 'Other' relationship.");
        }
    }

    private static ConnectionType ParseRelationType(string raw)
    {
        if (Enum.TryParse<ConnectionType>(raw, ignoreCase: true, out var ok)) return ok;
        throw new FriendsServiceException("invalid_relation_type",
            $"'{raw}' is not a valid relationship type.");
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
