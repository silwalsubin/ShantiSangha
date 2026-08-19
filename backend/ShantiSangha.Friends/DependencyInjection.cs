using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Detection;
using ShantiSangha.Friends.Jobs;
using ShantiSangha.Friends.Realtime;
using ShantiSangha.Friends.Services;
using ShantiSangha.Friends.Storage;
using ShantiSangha.Shared.Interfaces;
using StackExchange.Redis;

namespace ShantiSangha.Friends;

public static class DependencyInjection
{
    public static IServiceCollection AddFriendsModule(
        this IServiceCollection services,
        string connectionString,
        string mediaBucketName,
        string redisConnectionString)
    {
        services.AddDbContext<FriendsDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddSingleton(sp =>
        {
            var logger = sp.GetRequiredService<ILogger<FriendsMediaStorage>>();
            var region = Environment.GetEnvironmentVariable("AWS_REGION") ?? "us-east-1";
            return new FriendsMediaStorage(mediaBucketName, region, logger);
        });

        services.AddScoped<IFriendsService, FriendsService>();
        services.AddScoped<IFriendMessagesService, FriendMessagesService>();
        services.AddScoped<IFriendsQueryService, FriendsQueryService>();
        services.AddScoped<IFriendRequestsService, FriendRequestsService>();
        services.AddScoped<IConnectionsService, ConnectionsService>();
        services.AddScoped<IConnectionAttachmentsService, ConnectionAttachmentsService>();

        // Process-wide Redis multiplexer — Friends is the first consumer
        // (chat realtime fan-out). `AbortOnConnectFail = false` lets the
        // app boot even when Redis is briefly unreachable; the library
        // reconnects in the background and publishes silently no-op
        // until the link is restored.
        services.AddSingleton<IConnectionMultiplexer>(sp =>
        {
            var options = ConfigurationOptions.Parse(redisConnectionString);
            options.AbortOnConnectFail = false;
            options.ConnectRetry = 5;
            options.ConnectTimeout = 5000;
            options.ReconnectRetryPolicy = new ExponentialRetry(2000);
            return ConnectionMultiplexer.Connect(options);
        });

        // Realtime chat hub — singleton owns the per-instance WebSocket
        // registry. Cross-instance fan-out goes through Redis pub/sub so
        // multiple ECS tasks can serve the same conversation without
        // dropping subscribers on the other instance.
        services.AddSingleton<IChatRealtimeHub, RedisChatRealtimeHub>();
        // Expose the same hub instance under the Shared broadcaster interface so
        // other modules can fan out over the chat WebSocket.
        services.AddSingleton<ShantiSangha.Shared.Interfaces.IRealtimeBroadcaster>(
            sp => (ShantiSangha.Shared.Interfaces.IRealtimeBroadcaster)sp.GetRequiredService<IChatRealtimeHub>());

        // Cross-module abstraction so the WebSocket endpoint can answer
        // "is this user in this conversation?" without knowing about
        // friendships specifically. Group chats will plug in their own.
        services.AddScoped<IConversationMembershipService, FriendshipMembershipService>();

        // Reminder-suggestion detector: regex pre-filter is stateless +
        // pure (static), LLM extractor depends on Kernel (scoped), the
        // Hangfire job pulls them together. Hangfire will activate the
        // job via the DI container per invocation.
        services.AddScoped<IReminderExtractor, ReminderExtractor>();
        services.AddScoped<DetectReminderSuggestionJob>();
        services.AddScoped<IFriendMessageSuggestionService, FriendMessageSuggestionService>();

        return services;
    }
}
