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

        // IBKR Client Portal Gateway lives in its own ECS service. We hit it
        // through the public ALB URL (https://gateway.shantisangha.com) so the
        // request takes the same path the browser login does — direct Cloud
        // Map → gateway returns 403 Access Denied for reasons we never fully
        // tracked down, while the ALB path works.
        //
        // The gateway proxies to api.ibkr.com behind Akamai. Akamai's edge
        // rejects requests with an empty User-Agent header as "Access Denied"
        // (HTTP 403). .NET HttpClient sends no User-Agent by default, so we
        // have to add one explicitly or every call gets 403'd.
        services.AddHttpClient<IIbkrClient, IbkrClient>(c =>
        {
            c.BaseAddress = new Uri(ibkrGatewayBaseUrl);
            c.Timeout = TimeSpan.FromSeconds(30);
            c.DefaultRequestHeaders.UserAgent.ParseAdd("ShantiSangha/1.0");
        })
        .ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator,
        });

        return services;
    }
}
