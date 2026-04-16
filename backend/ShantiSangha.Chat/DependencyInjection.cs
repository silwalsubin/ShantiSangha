using Hangfire;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using ShantiSangha.Chat.AI;
using ShantiSangha.Chat.Data;
using ShantiSangha.Chat.Jobs;
using ShantiSangha.Chat.Safety;
using ShantiSangha.Chat.Services;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Chat;

public static class DependencyInjection
{
    public static IServiceCollection AddChatModule(
        this IServiceCollection services,
        NpgsqlDataSource dataSource)
    {
        services.AddDbContext<ChatDbContext>(options =>
            options.UseNpgsql(dataSource, o => o.UseVector()));

        services.AddScoped<JyotishContextService>();
        services.AddScoped<IChatService, ChatService>();
        services.AddScoped<ISafetyService, SafetyService>();
        services.AddScoped<ChatQueryService>();
        services.AddScoped<IChatQueryService>(sp => sp.GetRequiredService<ChatQueryService>());
        services.AddScoped<GenerateMessageEmbeddingJob>();
        services.AddScoped<GenerateConversationTitleJob>();

        return services;
    }

    public static void SubscribeChatEvents(this IServiceProvider services)
    {
        var eventBus = services.GetRequiredService<IEventBus>();

        eventBus.Subscribe<MessagesSavedEvent>(async (@event, ct) =>
        {
            var jobs = services.GetRequiredService<IBackgroundJobClient>();

            foreach (var msgId in @event.LastMessageIds)
                jobs.Enqueue<GenerateMessageEmbeddingJob>(j => j.RunAsync(msgId));

            // Generate title after first exchange (user + assistant = 2 messages)
            if (@event.MessageCount == 2)
                jobs.Enqueue<GenerateConversationTitleJob>(j => j.RunAsync(@event.ConversationId));

            await Task.CompletedTask;
        });
    }
}
