using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Chess.Data;
using ShantiSangha.Chess.Services;

namespace ShantiSangha.Chess;

public static class DependencyInjection
{
    public static IServiceCollection AddChessModule(this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<ChessDbContext>(options => options.UseNpgsql(connectionString));
        services.AddScoped<IChessGameService, ChessGameService>();
        // IRealtimeBroadcaster, IPushNotificationService, ICurrentUser are
        // registered globally (Friends / Api / Identity) — Chess just consumes them.
        return services;
    }
}
