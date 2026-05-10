using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Contracts;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Models;
using ShantiSangha.Friends.Realtime;
using ShantiSangha.Friends.Storage;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Services;

public class FriendMessagesService(
    FriendsDbContext db,
    FriendsMediaStorage storage,
    IProfileQueryService profileQuery,
    IPushNotificationService push,
    IChatRealtimeHub realtime,
    ILogger<FriendMessagesService> logger) : IFriendMessagesService
{
    private static readonly TimeSpan UploadUrlLifetime = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan DownloadUrlLifetime = TimeSpan.FromHours(1);

    private static readonly HashSet<string> AllowedImageTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg", "image/jpg", "image/png", "image/webp"
    };

    private static readonly HashSet<string> AllowedVoiceTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/mpeg", "audio/wav"
    };

    private const int MaxTextLength = 4000;
    private const int DefaultPageSize = 50;
    private const int MaxPageSize = 200;
    private const long MaxImageBytes = 8 * 1024 * 1024;
    private const long MaxVoiceBytes = 15 * 1024 * 1024;
    private const int MaxImageDimensionPx = 6000;
    private const int MaxVoiceDurationMs = 10 * 60 * 1000;

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

    public async Task<List<FriendMessageResponse>?> ListMediaMessagesAsync(
        Guid userId, Guid friendshipId, DateTime? before, int limit, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        var pageSize = Math.Clamp(limit <= 0 ? DefaultPageSize : limit, 1, MaxPageSize);
        // Image + Voice only — text is filtered out at the SQL level so a
        // chatty friendship doesn't pay the cost of paging through walls
        // of text to surface a handful of media. Soft-deleted rows are
        // also dropped so the archive doesn't show ghost entries.
        var query = db.Messages.Where(m =>
            m.FriendshipId == f.Id
            && m.DeletedAt == null
            && (m.Kind == FriendMessageKind.Image || m.Kind == FriendMessageKind.Voice));
        if (before.HasValue)
            query = query.Where(m => m.SentAt < before.Value);

        var rows = await query
            .OrderByDescending(m => m.SentAt)
            .Take(pageSize)
            .ToListAsync(ct);

        // Newest-first list — the archive renders most-recent at the top
        // (Apple Photos style), unlike the chat which renders oldest-first.
        return await MaterializeAsync(rows);
    }

    public async Task<FriendMessageResponse?> SendTextAsync(
        Guid userId, Guid friendshipId, string body, Guid? replyToMessageId = null, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        if (string.IsNullOrWhiteSpace(body))
            throw new FriendsServiceException("empty_message", "Message can't be empty.");
        if (body.Length > MaxTextLength)
            throw new FriendsServiceException("too_long", $"Message exceeds {MaxTextLength} characters.");

        await ValidateReplyTargetAsync(f.Id, replyToMessageId, ct);

        var msg = new FriendMessage
        {
            Id = Guid.NewGuid(),
            FriendshipId = f.Id,
            SenderUserId = userId,
            ReplyToMessageId = replyToMessageId,
            Kind = FriendMessageKind.Text,
            Body = body.Trim(),
            SentAt = DateTime.UtcNow
        };
        db.Messages.Add(msg);
        await db.SaveChangesAsync(ct);

        var dto = await MaterializeOneAsync(msg);
        // Realtime broadcast for both-online instant delivery; APNs push
        // remains the offline / app-backgrounded fallback.
        await BroadcastSafelyAsync("message_received", f.Id, new { conversationId = f.Id, message = dto }, ct);
        await NotifyRecipientAsync(f, userId, msg, ct);

        return dto;
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

        await ValidateReplyTargetAsync(f.Id, req.ReplyToMessageId, ct);
        await ValidateCommittedMediaAsync(kind, req, ct);

        var msg = new FriendMessage
        {
            Id = Guid.NewGuid(),
            FriendshipId = f.Id,
            SenderUserId = userId,
            ReplyToMessageId = req.ReplyToMessageId,
            Kind = kind,
            StorageKey = req.ObjectKey,
            DurationMs = kind == FriendMessageKind.Voice ? req.DurationMs : null,
            SentAt = DateTime.UtcNow
        };
        db.Messages.Add(msg);
        await db.SaveChangesAsync(ct);

        var dto = await MaterializeOneAsync(msg);
        await BroadcastSafelyAsync("message_received", f.Id, new { conversationId = f.Id, message = dto }, ct);
        await NotifyRecipientAsync(f, userId, msg, ct);

        return dto;
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

        // Tell the original sender (over realtime) that their message
        // was read so the iOS bubble can flip from single → double check.
        await BroadcastSafelyAsync("messages_read", f.Id, new
        {
            conversationId = f.Id,
            readByUserId = userId,
            lastMessageId = msg.Id,
            readAt = msg.ReadAt
        }, ct);

        return true;
    }

    public async Task<bool> MarkReadThroughAsync(
        Guid userId, Guid friendshipId, Guid lastMessageId, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return false;

        var last = await db.Messages.FirstOrDefaultAsync(
            m => m.Id == lastMessageId && m.FriendshipId == f.Id, ct);
        if (last is null) return false;
        if (last.SenderUserId == userId) return true;

        var readAt = DateTime.UtcNow;
        var rows = await db.Messages
            .Where(m => m.FriendshipId == f.Id
                && m.SenderUserId != userId
                && m.ReadAt == null
                && m.SentAt <= last.SentAt)
            .ToListAsync(ct);

        if (rows.Count == 0) return true;

        foreach (var row in rows)
            row.ReadAt = readAt;

        await db.SaveChangesAsync(ct);

        await BroadcastSafelyAsync("messages_read", f.Id, new
        {
            conversationId = f.Id,
            readByUserId = userId,
            lastMessageId,
            readAt
        }, ct);

        return true;
    }

    private static readonly TimeSpan EditWindow = TimeSpan.FromMinutes(15);

    public async Task<FriendMessageResponse?> EditTextAsync(
        Guid userId, Guid friendshipId, Guid messageId, string newBody, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        if (string.IsNullOrWhiteSpace(newBody))
            throw new FriendsServiceException("empty_message", "Message can't be empty.");
        if (newBody.Length > MaxTextLength)
            throw new FriendsServiceException("too_long", $"Message exceeds {MaxTextLength} characters.");

        var msg = await db.Messages.FirstOrDefaultAsync(
            m => m.Id == messageId && m.FriendshipId == f.Id, ct);
        if (msg is null)
            throw new FriendsServiceException("not_found", "Message not found.");
        if (msg.SenderUserId != userId)
            throw new FriendsServiceException("forbidden", "Only the sender can edit a message.");
        if (msg.Kind != FriendMessageKind.Text)
            throw new FriendsServiceException("wrong_kind", "Only text messages can be edited.");
        if (msg.DeletedAt is not null)
            throw new FriendsServiceException("already_deleted", "This message was deleted.");
        if (DateTime.UtcNow - msg.SentAt > EditWindow)
            throw new FriendsServiceException("edit_window_expired",
                $"Messages can only be edited within {EditWindow.TotalMinutes:F0} minutes of sending.");

        msg.Body = newBody.Trim();
        msg.EditedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);

        var dto = await MaterializeOneAsync(msg);
        await BroadcastSafelyAsync("message_edited", f.Id, new { conversationId = f.Id, message = dto }, ct);
        return dto;
    }

    public async Task<FriendMessageResponse?> DeleteAsync(
        Guid userId, Guid friendshipId, Guid messageId, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        var msg = await db.Messages.FirstOrDefaultAsync(
            m => m.Id == messageId && m.FriendshipId == f.Id, ct);
        if (msg is null) return null;
        if (msg.SenderUserId != userId)
            throw new FriendsServiceException("forbidden", "Only the sender can delete a message.");

        // Idempotent — already-deleted just returns the row as-is.
        if (msg.DeletedAt is not null)
            return await MaterializeOneAsync(msg);

        // Capture media key before clearing; remove the S3 object after
        // SaveChanges so a failed S3 delete doesn't roll back the row.
        var mediaKey = msg.StorageKey;

        msg.DeletedAt = DateTime.UtcNow;
        msg.Body = null;
        msg.StorageKey = null;
        msg.DurationMs = null;
        await db.SaveChangesAsync(ct);

        if (!string.IsNullOrEmpty(mediaKey))
        {
            try { await storage.DeleteAsync(mediaKey); }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to delete media for soft-deleted message {MessageId}", msg.Id);
            }
        }

        var dto = await MaterializeOneAsync(msg);
        await BroadcastSafelyAsync("message_deleted", f.Id, new
        {
            conversationId = f.Id,
            messageId = msg.Id
        }, ct);
        return dto;
    }

    public async Task<FriendMessageResponse?> ReactAsync(
        Guid userId, Guid friendshipId, Guid messageId, string emoji, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(emoji) || emoji.Length > 16)
            throw new FriendsServiceException("invalid_emoji", "Reaction must be a single emoji.");

        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        var msg = await db.Messages.FirstOrDefaultAsync(
            m => m.Id == messageId && m.FriendshipId == f.Id, ct);
        if (msg is null) return null;
        if (msg.DeletedAt is not null)
            throw new FriendsServiceException("already_deleted", "Can't react to a deleted message.");

        var existing = await db.MessageReactions.FirstOrDefaultAsync(
            r => r.MessageId == messageId && r.UserId == userId, ct);

        if (existing is not null)
        {
            // Idempotent: same emoji is a no-op (still re-broadcast the
            // current state so a UI that's out of sync can recover).
            if (existing.Emoji != emoji)
            {
                existing.Emoji = emoji;
                existing.CreatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync(ct);
            }
        }
        else
        {
            db.MessageReactions.Add(new FriendMessageReaction
            {
                MessageId = messageId,
                UserId = userId,
                Emoji = emoji,
                CreatedAt = DateTime.UtcNow
            });
            await db.SaveChangesAsync(ct);
        }

        var dto = await MaterializeOneAsync(msg);
        await BroadcastSafelyAsync("message_reactions_changed", f.Id, new
        {
            conversationId = f.Id,
            messageId = msg.Id,
            reactions = dto.Reactions
        }, ct);
        return dto;
    }

    public async Task<FriendMessageResponse?> UnreactAsync(
        Guid userId, Guid friendshipId, Guid messageId, CancellationToken ct = default)
    {
        var f = await GetFriendshipAsync(friendshipId, userId, ct);
        if (f is null) return null;

        var msg = await db.Messages.FirstOrDefaultAsync(
            m => m.Id == messageId && m.FriendshipId == f.Id, ct);
        if (msg is null) return null;

        var existing = await db.MessageReactions.FirstOrDefaultAsync(
            r => r.MessageId == messageId && r.UserId == userId, ct);
        if (existing is null)
        {
            // Idempotent: nothing to remove. Return the current state.
            return await MaterializeOneAsync(msg);
        }

        db.MessageReactions.Remove(existing);
        await db.SaveChangesAsync(ct);

        var dto = await MaterializeOneAsync(msg);
        await BroadcastSafelyAsync("message_reactions_changed", f.Id, new
        {
            conversationId = f.Id,
            messageId = msg.Id,
            reactions = dto.Reactions
        }, ct);
        return dto;
    }

    /// <summary>Wrap broadcasts so a hub failure (network blip, missing
    /// recipient, serialization edge case) never blocks the persisted
    /// state change. The REST response is the source of truth; the
    /// realtime event is a best-effort accelerator.</summary>
    private async Task BroadcastSafelyAsync(string kind, Guid conversationId, object payload, CancellationToken ct)
    {
        try { await realtime.PublishAsync(conversationId, kind, payload, ct); }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Realtime broadcast of {Kind} failed for conversation {ConversationId}", kind, conversationId);
        }
    }

    private async Task NotifyRecipientAsync(Friendship f, Guid senderId, FriendMessage msg, CancellationToken ct)
    {
        try
        {
            var recipientId = f.UserAId == senderId ? f.UserBId : f.UserAId;
            if (!await profileQuery.GetFriendMessageNotificationsEnabledAsync(recipientId, ct))
                return;

            var senderName = await profileQuery.GetDisplayNameAsync(senderId, ct) ?? "A friend";
            var preview = msg.Kind switch
            {
                FriendMessageKind.Text => string.IsNullOrWhiteSpace(msg.Body)
                    ? "sent a message"
                    : "sent you a message",
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
        FriendMessageReplyPreview? replyPreview = null;
        if (m.ReplyToMessageId is { } replyId)
        {
            var reply = await db.Messages
                .AsNoTracking()
                .FirstOrDefaultAsync(r => r.Id == replyId && r.FriendshipId == m.FriendshipId);

            if (reply is not null)
            {
                replyPreview = new FriendMessageReplyPreview(
                    reply.Id,
                    reply.SenderUserId,
                    reply.Kind.ToString(),
                    reply.DeletedAt.HasValue ? null : BuildReplyPreview(reply),
                    reply.DeletedAt.HasValue);
            }
        }

        string? mediaUrl = null;
        if (m.StorageKey is not null)
        {
            try { mediaUrl = await storage.GetPresignedDownloadUrlAsync(m.StorageKey, DownloadUrlLifetime); }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Failed to presign download URL for {Key}", m.StorageKey);
            }
        }

        // Don't leak the original body of a deleted message — clients
        // render a placeholder bubble for `DeletedAt != null`. Same for
        // media: presigning a URL after the S3 object is gone would
        // produce a 404, so skip that path entirely.
        var isDeleted = m.DeletedAt.HasValue;
        var safeBody = isDeleted ? null : m.Body;
        var safeMediaUrl = isDeleted ? null : mediaUrl;

        // Reactions: gather every (UserId, Emoji) row for this message
        // and roll up by emoji. Ordered by emoji so the iOS pill row is
        // stable across renders. Deleted messages drop reactions —
        // the bubble is replaced by a placeholder anyway.
        List<FriendMessageReactionSummary> reactions;
        if (isDeleted)
        {
            reactions = new List<FriendMessageReactionSummary>();
        }
        else
        {
            var rows = await db.MessageReactions
                .AsNoTracking()
                .Where(r => r.MessageId == m.Id)
                .ToListAsync();
            reactions = rows
                .GroupBy(r => r.Emoji)
                .OrderBy(g => g.Key)
                .Select(g => new FriendMessageReactionSummary(
                    g.Key,
                    g.Select(r => r.UserId).ToList()))
                .ToList();
        }

        return new FriendMessageResponse(
            m.Id,
            m.FriendshipId,
            m.FriendshipId,         // ConversationId == FriendshipId for 1:1
            m.SenderUserId,
            m.ReplyToMessageId,
            replyPreview,
            m.Kind.ToString(),
            safeBody,
            safeMediaUrl,
            m.DurationMs,
            m.SentAt,
            m.ReadAt,
            m.EditedAt,
            m.DeletedAt,
            reactions);
    }

    private static string ExtensionForImage(string contentType) => contentType.ToLowerInvariant() switch
    {
        "image/jpeg" or "image/jpg" => ".jpg",
        "image/png" => ".png",
        "image/heic" => ".heic",
        "image/webp" => ".webp",
        _ => ".bin"
    };

    private static string BuildReplyPreview(FriendMessage m) => m.Kind switch
    {
        FriendMessageKind.Text => string.IsNullOrWhiteSpace(m.Body)
            ? "Message"
            : (m.Body.Length > 120 ? m.Body[..120] + "…" : m.Body),
        FriendMessageKind.Image => "Photo",
        FriendMessageKind.Voice => "Voice message",
        _ => "Message"
    };

    private async Task ValidateReplyTargetAsync(Guid friendshipId, Guid? replyToMessageId, CancellationToken ct)
    {
        if (replyToMessageId is null) return;

        var exists = await db.Messages.AnyAsync(
            m => m.Id == replyToMessageId.Value && m.FriendshipId == friendshipId, ct);
        if (!exists)
            throw new FriendsServiceException("invalid_reply", "Reply target does not belong to this chat.");
    }

    private static string ExtensionForVoice(string contentType) => contentType.ToLowerInvariant() switch
    {
        "audio/mp4" or "audio/m4a" or "audio/x-m4a" => ".m4a",
        "audio/aac" => ".aac",
        "audio/mpeg" => ".mp3",
        "audio/wav" => ".wav",
        _ => ".bin"
    };

    private async Task ValidateCommittedMediaAsync(
        FriendMessageKind kind, CommitMediaMessageRequest req, CancellationToken ct)
    {
        var info = await storage.GetObjectInfoAsync(req.ObjectKey)
            ?? throw new FriendsServiceException("missing_object", "Uploaded media was not found.");

        var contentType = info.ContentType ?? "";
        if (kind == FriendMessageKind.Image)
        {
            if (!AllowedImageTypes.Contains(contentType))
                throw new FriendsServiceException("unsupported_type", "Uploaded image type is not supported.");
            if (info.ContentLength <= 0 || info.ContentLength > MaxImageBytes)
                throw new FriendsServiceException("file_too_large", $"Images must be under {MaxImageBytes / 1024 / 1024} MB.");

            var prefix = await storage.ReadPrefixAsync(req.ObjectKey, 64 * 1024);
            var dimensions = TryReadImageDimensions(prefix, contentType);
            if (dimensions is null)
                throw new FriendsServiceException("invalid_image", "Uploaded image could not be validated.");
            if (dimensions.Value.Width > MaxImageDimensionPx || dimensions.Value.Height > MaxImageDimensionPx)
                throw new FriendsServiceException("image_too_large", $"Images must be at most {MaxImageDimensionPx}px wide or tall.");
        }
        else if (kind == FriendMessageKind.Voice)
        {
            if (!AllowedVoiceTypes.Contains(contentType))
                throw new FriendsServiceException("unsupported_type", "Uploaded voice type is not supported.");
            if (info.ContentLength <= 0 || info.ContentLength > MaxVoiceBytes)
                throw new FriendsServiceException("file_too_large", $"Voice messages must be under {MaxVoiceBytes / 1024 / 1024} MB.");
            if (req.DurationMs is null or <= 0 or > MaxVoiceDurationMs)
                throw new FriendsServiceException("invalid_duration", "Voice message duration is not valid.");
        }
    }

    private static (int Width, int Height)? TryReadImageDimensions(byte[] bytes, string contentType)
    {
        if (bytes.Length >= 24 &&
            bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47)
        {
            return (ReadBigEndianInt32(bytes, 16), ReadBigEndianInt32(bytes, 20));
        }

        if (bytes.Length >= 12 &&
            bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
            bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50)
        {
            return TryReadWebpDimensions(bytes);
        }

        if (bytes.Length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8)
        {
            return TryReadJpegDimensions(bytes);
        }

        return null;
    }

    private static (int Width, int Height)? TryReadJpegDimensions(byte[] bytes)
    {
        var i = 2;
        while (i + 9 < bytes.Length)
        {
            if (bytes[i] != 0xFF) { i++; continue; }
            while (i < bytes.Length && bytes[i] == 0xFF) i++;
            if (i >= bytes.Length) return null;
            var marker = bytes[i++];
            if (marker == 0xD9 || marker == 0xDA) return null;
            if (i + 1 >= bytes.Length) return null;
            var length = (bytes[i] << 8) + bytes[i + 1];
            if (length < 2 || i + length > bytes.Length) return null;

            if (marker is >= 0xC0 and <= 0xC3 or >= 0xC5 and <= 0xC7 or >= 0xC9 and <= 0xCB or >= 0xCD and <= 0xCF)
            {
                if (i + 7 >= bytes.Length) return null;
                var height = (bytes[i + 3] << 8) + bytes[i + 4];
                var width = (bytes[i + 5] << 8) + bytes[i + 6];
                return (width, height);
            }

            i += length;
        }

        return null;
    }

    private static (int Width, int Height)? TryReadWebpDimensions(byte[] bytes)
    {
        if (bytes.Length < 30) return null;
        var chunk = System.Text.Encoding.ASCII.GetString(bytes, 12, 4);
        if (chunk == "VP8X" && bytes.Length >= 30)
        {
            var width = 1 + bytes[24] + (bytes[25] << 8) + (bytes[26] << 16);
            var height = 1 + bytes[27] + (bytes[28] << 8) + (bytes[29] << 16);
            return (width, height);
        }
        if (chunk == "VP8 " && bytes.Length >= 30)
        {
            var width = bytes[26] + ((bytes[27] & 0x3F) << 8);
            var height = bytes[28] + ((bytes[29] & 0x3F) << 8);
            return (width, height);
        }
        if (chunk == "VP8L" && bytes.Length >= 25)
        {
            var b0 = bytes[21];
            var b1 = bytes[22];
            var b2 = bytes[23];
            var b3 = bytes[24];
            var width = 1 + (((b1 & 0x3F) << 8) | b0);
            var height = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6));
            return (width, height);
        }
        return null;
    }

    private static int ReadBigEndianInt32(byte[] bytes, int offset) =>
        (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
}
