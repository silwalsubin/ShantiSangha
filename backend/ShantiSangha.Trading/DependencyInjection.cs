using Amazon.Lambda;
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
        string wisecatFunctionName)
    {
        services.AddDbContext<TradingDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddScoped<IWatchlistService, WatchlistService>();
        services.AddScoped<ITradingSignalService, TradingSignalService>();
        services.AddScoped<IMarketDataClient, MarketDataClient>();
        services.AddScoped<IPortfolioService, PortfolioService>();
        services.AddScoped<IStrategySettingsService, StrategySettingsService>();

        services.AddScoped<RefreshMarketDataJob>();
        services.AddScoped<GenerateDailyTradingSignalsJob>();

        // AWS Lambda client — uses the default credential chain, which on
        // ECS Fargate resolves to the task role automatically.
        services.AddSingleton<IAmazonLambda>(_ => new AmazonLambdaClient());
        services.AddSingleton(new WisecatLambdaConfig(wisecatFunctionName));

        return services;
    }
}
