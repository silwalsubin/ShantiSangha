using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Identity.Data;
using ShantiSangha.Identity.Models;
using ShantiSangha.Identity.Services;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity;

public static class DependencyInjection
{
    public static IServiceCollection AddIdentityModule(this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<IdentityDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddScoped<ICurrentUser, CurrentUserService>();
        services.AddScoped<IUserService, UserService>();
        services.AddScoped<IProfileQueryService, ProfileQueryService>();

        return services;
    }

    /// <summary>
    /// Subscribe to cross-domain events. Call after the service provider is built.
    /// </summary>
    public static void UseIdentityModule(this IServiceProvider services)
    {
        var eventBus = services.GetRequiredService<IEventBus>();

        eventBus.Subscribe<SafetyEventOccurredEvent>(async (@event, ct) =>
        {
            using var scope = services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<IdentityDbContext>();

            var safetyEvent = new SafetyEvent
            {
                Id = Guid.NewGuid(),
                UserId = @event.UserId,
                EventType = Enum.TryParse<SafetyEventType>(@event.EventType, out var parsed)
                    ? parsed
                    : SafetyEventType.ModerationFlagged,
                TriggerContent = @event.TriggerContent,
                Details = @event.Details,
                ConversationId = @event.ConversationId,
                CreatedAt = DateTime.UtcNow
            };

            db.SafetyEvents.Add(safetyEvent);
            await db.SaveChangesAsync(ct);
        });
    }
}
