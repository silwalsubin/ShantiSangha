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

namespace ShantiSangha.Chat;

public static class DependencyInjection
{
    public static IServiceCollection AddChatModule(
        this IServiceCollection services,
        NpgsqlDataSource dataSource)
    {
        services.AddDbContext<ChatDbContext>(options =>
            options.UseNpgsql(dataSource, o => o.UseVector()));

        services.AddScoped<IChatService, ChatService>();
        services.AddScoped<ISafetyService, SafetyService>();
        services.AddScoped<ChatQueryService>();
        services.AddScoped<IChatQueryService>(sp => sp.GetRequiredService<ChatQueryService>());
        services.AddScoped<IConversationStore, ConversationStore>();
        services.AddScoped<GenerateConversationTitleJob>();

        return services;
    }

    public static void SubscribeChatEvents(this IServiceProvider services)
    {
        var eventBus = services.GetRequiredService<IEventBus>();

        eventBus.Subscribe<MessagesSavedEvent>(async (@event, ct) =>
        {
            var jobs = services.GetRequiredService<IBackgroundJobClient>();

            // Generate title after the first real exchange. Count is 2 when the
            // user spoke first, 3 when the companion opened the conversation
            // (opener + user + assistant). The event only fires after assistant
            // replies, so exactly one of these values occurs per conversation.
            if (@event.MessageCount is 2 or 3)
                jobs.Enqueue<GenerateConversationTitleJob>(j => j.RunAsync(@event.ConversationId));

            await Task.CompletedTask;
        });
    }
}
