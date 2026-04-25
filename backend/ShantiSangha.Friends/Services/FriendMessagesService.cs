using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Models;
using ShantiSangha.Friends.Storage;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

public class FriendMessagesService(
    FriendsDbContext db,
    FriendsMediaStorage storage,
    IProfileQueryService profileQuery,
    IPushNotificationService push,
    ILogger<FriendMessagesService> logger) : IFriendMessagesService
{
    private static readonly TimeSpan UploadUrlLifetime = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan DownloadUrlLifetime = TimeSpan.FromHours(1);

    private static readonly HashSet<string> AllowedImageTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg", "image/jpg", "image/png", "image/heic", "image/webp"
    };

    private static readonly HashSet<string> AllowedVoiceTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/mpeg", "audio/wav"
    };

    private const int MaxTextLength = 4000;
    private const int DefaultPageSize = 50;
    private const int MaxPageSize = 200;

    public async Task<List<FriendMessageResponse>?> ListMessagesAsync(
        Guid userId, Guid friendshipId, DateTime? before, int limit, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        var pageSize = Math.Clamp(limit <= 0 ? DefaultPageSize : limit, 1, MaxPageSize);
        var query = db.Messages.Where(m => m.FriendshipId == f.Id);
        if (before.HasValue)
            query = query.Where(m => m.SentAt < before.Value);

        var rows = await query
            .OrderByDescending(m => m.SentAt)
            .Take(pageSize)
            .ToListAsync(ct);

        rows.Reverse();
        return await MaterializeAsync(rows);
    }

    public async Task<FriendMessageResponse?> SendTextAsync(
        Guid userId, Guid friendshipId, string body, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        if (string.IsNullOrWhiteSpace(body))
            throw new FriendsServiceException("empty_message", "Message can't be empty.");
        if (body.Length > MaxTextLength)
            throw new FriendsServiceException("too_long", $"Message exceeds {MaxTextLength} characters.");

        var msg = new FriendMessage
        {
            Id = Guid.NewGuid(),
            FriendshipId = f.Id,
            SenderUserId = userId,
            Kind = FriendMessageKind.Text,
            Body = body.Trim(),
            SentAt = DateTime.UtcNow
        };
        db.Messages.Add(msg);
        await db.SaveChangesAsync(ct);

        await NotifyRecipientAsync(f, userId, msg, ct);

        return await MaterializeOneAsync(msg);
    }

    public async Task<CreateMediaUploadResponse?> CreateImageUploadAsync(
        Guid userId, Guid friendshipId, string contentType, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        if (!AllowedImageTypes.Contains(contentType))
            throw new FriendsServiceException("unsupported_type", "Unsupported image type.");

        var ext = ExtensionForImage(contentType);
        var key = $"friends/{f.Id}/images/{Guid.NewGuid()}{ext}";
        var url = await storage.GetPresignedUploadUrlAsync(key, contentType, UploadUrlLifetime);
        return new CreateMediaUploadResponse(key, url, DateTime.UtcNow.Add(UploadUrlLifetime));
    }

    public async Task<CreateMediaUploadResponse?> CreateVoiceUploadAsync(
        Guid userId, Guid friendshipId, string contentType, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        if (!AllowedVoiceTypes.Contains(contentType))
            throw new FriendsServiceException("unsupported_type", "Unsupported voice type.");

        var ext = ExtensionForVoice(contentType);
        var key = $"friends/{f.Id}/voice/{Guid.NewGuid()}{ext}";
        var url = await storage.GetPresignedUploadUrlAsync(key, contentType, UploadUrlLifetime);
        return new CreateMediaUploadResponse(key, url, DateTime.UtcNow.Add(UploadUrlLifetime));
    }

    public async Task<FriendMessageResponse?> CommitImageMessageAsync(
        Guid userId, Guid friendshipId, CommitMediaMessageRequest req, CancellationToken ct = default) =>
        await CommitMediaAsync(userId, friendshipId, FriendMessageKind.Image, req, ct);

    public async Task<FriendMessageResponse?> CommitVoiceMessageAsync(
        Guid userId, Guid friendshipId, CommitMediaMessageRequest req, CancellationToken ct = default) =>
        await CommitMediaAsync(userId, friendshipId, FriendMessageKind.Voice, req, ct);

    private async Task<FriendMessageResponse?> CommitMediaAsync(
        Guid userId, Guid friendshipId, FriendMessageKind kind, CommitMediaMessageRequest req, CancellationToken ct)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        if (string.IsNullOrWhiteSpace(req.ObjectKey))
            throw new FriendsServiceException("missing_key", "Object key is required.");
        var prefix = kind == FriendMessageKind.Image ? $"friends/{f.Id}/images/" : $"friends/{f.Id}/voice/";
        if (!req.ObjectKey.StartsWith(prefix, StringComparison.Ordinal))
            throw new FriendsServiceException("invalid_key", "Object key does not belong to this friendship.");

        var msg = new FriendMessage
        {
            Id = Guid.NewGuid(),
            FriendshipId = f.Id,
            SenderUserId = userId,
            Kind = kind,
            StorageKey = req.ObjectKey,
            DurationMs = kind == FriendMessageKind.Voice ? req.DurationMs : null,
            SentAt = DateTime.UtcNow
        };
        db.Messages.Add(msg);
        await db.SaveChangesAsync(ct);

        await NotifyRecipientAsync(f, userId, msg, ct);

        return await MaterializeOneAsync(msg);
    }

    public async Task<bool> MarkReadAsync(
        Guid userId, Guid friendshipId, Guid messageId, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return false;

        var msg = await db.Messages.FirstOrDefaultAsync(
            m => m.Id == messageId && m.FriendshipId == f.Id, ct);
        if (msg is null) return false;
        if (msg.SenderUserId == userId) return true;
        if (msg.ReadAt is not null) return true;

        msg.ReadAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    private async Task NotifyRecipientAsync(Friendship f, Guid senderId, FriendMessage msg, CancellationToken ct)
    {
        try
        {
            var recipientId = f.UserAId == senderId ? f.UserBId : f.UserAId;
            var senderName = await profileQuery.GetDisplayNameAsync(senderId, ct) ?? "A friend";
            var preview = msg.Kind switch
            {
                FriendMessageKind.Text => string.IsNullOrWhiteSpace(msg.Body)
                    ? "sent a message"
                    : (msg.Body!.Length > 120 ? msg.Body![..120] + "…" : msg.Body!),
                FriendMessageKind.Image => "sent a photo",
                FriendMessageKind.Voice => "sent a voice message",
                _ => "sent a message"
            };

            await push.SendAlertPushAsync(recipientId,
                title: senderName,
                body: preview,
                data: new Dictionary<string, string>
                {
                    ["type"] = "friend_message",
                    ["friendshipId"] = f.Id.ToString(),
                    ["messageId"] = msg.Id.ToString()
                }, ct: ct);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Failed to send friend_message push for message {MessageId}", msg.Id);
        }
    }

    private async Task<Friendship?> GetFriendshipAsync(Guid friendshipId, Guid userId, CancellationToken ct) =>
        await db.Friendships.FirstOrDefaultAsync(
            f => f.Id == friendshipId && (f.UserAId == userId || f.UserBId == userId), ct);

    private async Task<List<FriendMessageResponse>> MaterializeAsync(List<FriendMessage> messages)
    {
        var result = new List<FriendMessageResponse>(messages.Count);
        foreach (var m in messages)
            result.Add(await MaterializeOneAsync(m));
        return result;
    }

    private async Task<FriendMessageResponse> MaterializeOneAsync(FriendMessage m)
    {
        string? mediaUrl = null;
        if (m.StorageKey is not null)
        {
            try { mediaUrl = await storage.GetPresignedDownloadUrlAsync(m.StorageKey, DownloadUrlLifetime); }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to presign download URL for {Key}", m.StorageKey);
            }
        }

        return new FriendMessageResponse(
            m.Id, m.FriendshipId, m.SenderUserId,
            m.Kind.ToString(), m.Body, mediaUrl, m.DurationMs,
            m.SentAt, m.ReadAt);
    }

    private static string ExtensionForImage(string contentType) => contentType.ToLowerInvariant() switch
    {
        "image/jpeg" or "image/jpg" => ".jpg",
        "image/png" => ".png",
        "image/heic" => ".heic",
        "image/webp" => ".webp",
        _ => ".bin"
    };

    private static string ExtensionForVoice(string contentType) => contentType.ToLowerInvariant() switch
    {
        "audio/mp4" or "audio/m4a" or "audio/x-m4a" => ".m4a",
        "audio/aac" => ".aac",
        "audio/mpeg" => ".mp3",
        "audio/wav" => ".wav",
        _ => ".bin"
    };
}
