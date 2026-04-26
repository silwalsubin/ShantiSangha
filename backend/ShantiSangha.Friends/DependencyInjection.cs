using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ShantiSangha.Friends.Data;
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

        return services;
    }
}
