using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Reminders.Data;
using ShantiSangha.Reminders.Services;

namespace ShantiSangha.Reminders;

public static class DependencyInjection
{
    public static IServiceCollection AddRemindersModule(
        this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<RemindersDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddScoped<IReminderService, ReminderService>();

        return services;
    }
}
