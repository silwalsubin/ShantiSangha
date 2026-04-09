using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Journal.Data;
using ShantiSangha.Journal.Services;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Journal;

public static class DependencyInjection
{
    public static IServiceCollection AddJournalModule(
        this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<JournalDbContext>(options =>
            options.UseNpgsql(connectionString, o => o.UseVector()));

        services.AddScoped<IJournalService, JournalService>();
        services.AddScoped<IJournalQueryService, JournalQueryService>();
        services.AddScoped<IJournalSearchService, JournalSearchService>();

        return services;
    }

    public static void SubscribeJournalEvents(this IServiceProvider serviceProvider)
    {
        var eventBus = serviceProvider.GetRequiredService<IEventBus>();

        eventBus.Subscribe<VoiceTranscribedEvent>(async (e, ct) =>
        {
            using var scope = serviceProvider.CreateScope();
            var journalService = scope.ServiceProvider.GetRequiredService<IJournalService>();
            await ((JournalService)journalService).HandleVoiceTranscribedAsync(e, ct);
        });
    }
}
