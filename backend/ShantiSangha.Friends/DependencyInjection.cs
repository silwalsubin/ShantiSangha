using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Data;
using ShantiSangha.Friends.Realtime;
using ShantiSangha.Friends.Services;
using ShantiSangha.Friends.Storage;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends;

public static class DependencyInjection
{
    public static IServiceCollection AddFriendsModule(
        this IServiceCollection services,
        string connectionString,
        string mediaBucketName)
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

        // Realtime chat hub — singleton holds the live WebSocket registry
        // in process. Future multi-instance scale will swap this for a
        // Redis-backed implementation; the interface stays the same.
        services.AddSingleton<IChatRealtimeHub, InMemoryChatRealtimeHub>();

        // Cross-module abstraction so the WebSocket endpoint can answer
        // "is this user in this conversation?" without knowing about
        // friendships specifically. Group chats will plug in their own.
        services.AddScoped<IConversationMembershipService, FriendshipMembershipService>();

        return services;
    }
}
