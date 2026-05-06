using System.Net.Http.Headers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Trading.Data;
using ShantiSangha.Trading.Jobs;
using ShantiSangha.Trading.Services;

namespace ShantiSangha.Trading;

public static class DependencyInjection
{
    public static IServiceCollection AddTradingModule(
        this IServiceCollection services,
        string connectionString,
        string wisecatBaseUrl,
        string wisecatInternalKey)
    {
        services.AddDbContext<TradingDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddSingleton<IIpoChartCsvLoader, IpoChartCsvLoader>();

        services.AddScoped<IWatchlistService, WatchlistService>();
        services.AddScoped<IStockChartService, StockChartService>();
        services.AddSingleton<ITransitAspectService, TransitAspectService>();
        services.AddScoped<IAstroSignalService, AstroSignalService>();
        services.AddScoped<ITradingSignalService, TradingSignalService>();
        services.AddScoped<IMarketDataClient, MarketDataClient>();

        services.AddScoped<RefreshMarketDataJob>();
        services.AddScoped<GenerateDailyTradingSignalsJob>();

        services.AddHttpClient(MarketDataClient.HttpClientName, client =>
        {
            client.BaseAddress = new Uri(wisecatBaseUrl);
            client.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", wisecatInternalKey);
            client.Timeout = TimeSpan.FromSeconds(30);
        });

        return services;
    }
}
