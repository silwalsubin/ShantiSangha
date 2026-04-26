using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Notifications.Contracts;
using ShantiSangha.Notifications.Data;
using ShantiSangha.Notifications.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Notifications.Services;

public interface IInboxService
{
    Task<NotificationListResponse> ListAsync(Guid userId, int page, int pageSize, CancellationToken ct = default);
    Task<int> GetUnreadCountAsync(Guid userId, CancellationToken ct = default);
    /// <summary>Bulk-stamp every unread notification for the user as
    /// viewed. Returns how many rows were updated. Called when the user
    /// opens the inbox.</summary>
    Task<int> MarkAllViewedAsync(Guid userId, CancellationToken ct = default);
}

public class NotificationService(NotificationsDbContext db) : INotificationService, IInboxService
{
    private static readonly JsonSerializerOptions PayloadOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public async Task<Guid> EnqueueAsync(
        Guid recipientUserId,
        string type,
        object? payload = null,
        CancellationToken ct = default)
    {
        var notification = new AppNotification
        {
            Id = Guid.NewGuid(),
            RecipientUserId = recipientUserId,
            Type = type,
            PayloadJson = payload is null ? "{}" : JsonSerializer.Serialize(payload, PayloadOptions),
            CreatedAt = DateTime.UtcNow,
            ViewedAt = null
        };
        db.Notifications.Add(notification);
        await db.SaveChangesAsync(ct);
        return notification.Id;
    }

    public async Task<NotificationListResponse> ListAsync(Guid userId, int page, int pageSize, CancellationToken ct = default)
    {
        var clampedPage = Math.Max(page, 1);
        var clampedPageSize = Math.Clamp(pageSize <= 0 ? 30 : pageSize, 1, 100);

        var unreadCount = await db.Notifications
            .CountAsync(n => n.RecipientUserId == userId && n.ViewedAt == null, ct);

        var rows = await db.Notifications
            .Where(n => n.RecipientUserId == userId)
            .OrderByDescending(n => n.CreatedAt)
            .Skip((clampedPage - 1) * clampedPageSize)
            .Take(clampedPageSize)
            .Select(n => new NotificationResponse(
                n.Id,
                n.Type,
                n.PayloadJson,
                n.CreatedAt,
                n.ViewedAt))
            .ToListAsync(ct);

        return new NotificationListResponse(unreadCount, rows);
    }

    public async Task<int> GetUnreadCountAsync(Guid userId, CancellationToken ct = default)
    {
        return await db.Notifications
            .CountAsync(n => n.RecipientUserId == userId && n.ViewedAt == null, ct);
    }

    public async Task<int> MarkAllViewedAsync(Guid userId, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        // ExecuteUpdateAsync (EF Core 8) does the bulk update in one round
        // trip — no need to load rows into memory just to flip a flag.
        return await db.Notifications
            .Where(n => n.RecipientUserId == userId && n.ViewedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(n => n.ViewedAt, now), ct);
    }
}
