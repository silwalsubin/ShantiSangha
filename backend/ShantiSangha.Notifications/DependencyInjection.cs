using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Notifications.Data;
using ShantiSangha.Notifications.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Notifications;

public static class DependencyInjection
{
    public static IServiceCollection AddNotificationsModule(
        this IServiceCollection services,
        string connectionString)
    {
        services.AddDbContext<NotificationsDbContext>(options =>
            options.UseNpgsql(connectionString));

        // NotificationService implements both INotificationService (the
        // cross-module entry point in Shared, used by Friends/Chat/etc.
        // to enqueue) and IInboxService (the internal interface the
        // controller uses to read + mark-viewed). One instance, two
        // facets so other modules don't accidentally see the inbox API.
        services.AddScoped<NotificationService>();
        services.AddScoped<INotificationService>(sp => sp.GetRequiredService<NotificationService>());
        services.AddScoped<IInboxService>(sp => sp.GetRequiredService<NotificationService>());

        return services;
    }
}
