using Hangfire;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using ShantiSangha.Memory.Data;
using ShantiSangha.Memory.Jobs;
using ShantiSangha.Memory.Services;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Memory;

public static class DependencyInjection
{
    public static IServiceCollection AddMemoryModule(
        this IServiceCollection services, NpgsqlDataSource dataSource)
    {
        services.AddDbContext<MemoryDbContext>(options =>
            options.UseNpgsql(dataSource, o => o.UseVector()));

        services.AddScoped<MemoryIndexer>();
        services.AddScoped<IMemoryQueryService, MemoryQueryService>();
        services.AddScoped<IndexJournalJob>();
        services.AddScoped<IndexChatMessagesJob>();
        services.AddScoped<PurgeMemoryJob>();
        services.AddScoped<BackfillMemoryJob>();

        return services;
    }

    /// Handlers stay thin — the in-process event bus awaits subscribers
    /// sequentially, so all real work is pushed to Hangfire.
    public static void SubscribeMemoryEvents(this IServiceProvider services)
    {
        var eventBus = services.GetRequiredService<IEventBus>();
        var jobs = services.GetRequiredService<IBackgroundJobClient>();

        eventBus.Subscribe<JournalCreatedEvent>((e, _) =>
        {
            jobs.Enqueue<IndexJournalJob>(j => j.RunAsync(e.JournalId));
            return Task.CompletedTask;
        });

        eventBus.Subscribe<JournalUpdatedEvent>((e, _) =>
        {
            jobs.Enqueue<IndexJournalJob>(j => j.RunAsync(e.JournalId));
            return Task.CompletedTask;
        });

        eventBus.Subscribe<JournalDeletedEvent>((e, _) =>
        {
            jobs.Enqueue<PurgeMemoryJob>(j => j.RunForSourceAsync("journal", e.JournalId));
            return Task.CompletedTask;
        });

        // Voice notes are NOT subscribed directly: transcripts become journal
        // drafts, which arrive here through JournalCreatedEvent — subscribing
        // VoiceTranscribedEvent too would double-index the same words.
        eventBus.Subscribe<MessagesSavedEvent>((e, _) =>
        {
            jobs.Enqueue<IndexChatMessagesJob>(j => j.RunAsync(e.UserId, e.LastMessageIds.ToArray()));
            return Task.CompletedTask;
        });

        eventBus.Subscribe<ConversationDeletedEvent>((e, _) =>
        {
            jobs.Enqueue<PurgeMemoryJob>(j => j.RunForConversationAsync(e.ConversationId));
            return Task.CompletedTask;
        });

        // Sweep pre-Memory content into the index. Idempotent — see the job.
        jobs.Enqueue<BackfillMemoryJob>(j => j.RunAsync());
    }
}
