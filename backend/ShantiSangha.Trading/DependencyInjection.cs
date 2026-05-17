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
        string wisecatFunctionName,
        string ibkrGatewayBaseUrl)
    {
        services.AddDbContext<TradingDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddScoped<ITradingSignalService, TradingSignalService>();
        services.AddScoped<IMarketDataClient, MarketDataClient>();
        services.AddScoped<IPortfolioService, PortfolioService>();
        services.AddScoped<IStrategySettingsService, StrategySettingsService>();
        services.AddScoped<IStrategyBacktestService, StrategyBacktestService>();
        services.AddScoped<IIbkrPortfolioSyncService, IbkrPortfolioSyncService>();

        services.AddScoped<RefreshMarketDataJob>();
        services.AddScoped<GenerateDailyTradingSignalsJob>();
        services.AddScoped<IbkrPortfolioSyncJob>();
        services.AddScoped<IbkrSessionKeepaliveJob>();

        // AWS Lambda client — uses the default credential chain, which on
        // ECS Fargate resolves to the task role automatically.
        services.AddSingleton<IAmazonLambda>(_ => new AmazonLambdaClient());
        services.AddSingleton(new WisecatLambdaConfig(wisecatFunctionName));

        // IBKR Client Portal Gateway lives in the same ECS task as a
        // sidecar container, exposed on localhost. The gateway terminates
        // TLS itself with a self-signed certificate — fine because traffic
        // never leaves the task's network namespace, but the .NET HTTP
        // client has to opt out of certificate validation.
        services.AddHttpClient<IIbkrClient, IbkrClient>(c =>
        {
            c.BaseAddress = new Uri(ibkrGatewayBaseUrl);
            c.Timeout = TimeSpan.FromSeconds(30);
        })
        .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator,
        });

        return services;
    }
}
