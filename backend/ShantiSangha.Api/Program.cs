using Hangfire;
using Hangfire.PostgreSql;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.SemanticKernel;
using Serilog;
using ShantiSangha.Api;
using ShantiSangha.Api.Routes;
using ShantiSangha.Core.Services;
using ShantiSangha.Infrastructure.AI;
using ShantiSangha.Infrastructure.Data;
using ShantiSangha.Infrastructure.Jobs;
using ShantiSangha.Infrastructure.Storage;
using System.Net.Http.Headers;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    // Serilog
    builder.Host.UseSerilog((ctx, services, config) => config
        .ReadFrom.Configuration(ctx.Configuration)
        .ReadFrom.Services(services)
        .Enrich.FromLogContext()
        .WriteTo.Console(outputTemplate: "[{Timestamp:HH:mm:ss} {Level:u3}] {Message:lj} {Properties:j}{NewLine}{Exception}"));

    // Config — fails fast at startup if any required env var is missing
    var appConfig = AppConfig.Load(builder.Configuration);
    builder.Services.AddSingleton(appConfig);

    // Database
    builder.Services.AddDbContext<AppDbContext>(opts =>
        opts.UseNpgsql(appConfig.DatabaseUrl, npgsql =>
            npgsql.UseVector()));

    // HTTP client for OpenAI moderation API
    builder.Services.AddHttpClient("OpenAI", client =>
    {
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", appConfig.OpenAiApiKey);
    });

    // Semantic Kernel + OpenAI (chat + embeddings)
#pragma warning disable SKEXP0010
    builder.Services.AddKernel()
        .AddOpenAIChatCompletion("gpt-4o", appConfig.OpenAiApiKey)
        .AddOpenAIEmbeddingGenerator("text-embedding-3-small", appConfig.OpenAiApiKey);
#pragma warning restore SKEXP0010

    // Safety + Chat services
    builder.Services.AddScoped<ISafetyService, SafetyService>();
    builder.Services.AddScoped<IChatService, ChatService>();

    // R2 / S3-compatible storage
    builder.Services.AddSingleton(sp =>
    {
        var cfg = sp.GetRequiredService<AppConfig>();
        var log = sp.GetRequiredService<ILogger<StorageService>>();
        return new StorageService(cfg.R2ServiceUrl, cfg.R2AccessKeyId, cfg.R2SecretAccessKey, cfg.R2BucketName, log);
    });

    // Background job classes (Hangfire resolves these via DI)
    builder.Services.AddScoped<GenerateSummaryJob>();
    builder.Services.AddScoped<GenerateEmbeddingJob>();
    builder.Services.AddScoped<ExtractInsightsJob>();
    builder.Services.AddScoped<TranscribeVoiceJob>();

    // Hangfire — PostgreSQL-backed job queue
    builder.Services.AddHangfire(config => config
        .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
        .UseSimpleAssemblyNameTypeSerializer()
        .UseRecommendedSerializerSettings()
        .UsePostgreSqlStorage(o => o.UseNpgsqlConnection(appConfig.DatabaseUrl)));
    builder.Services.AddHangfireServer();

    // Auth — Clerk issues standard JWTs validated here
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(opts =>
        {
            opts.Authority = appConfig.ClerkAuthority;
            opts.TokenValidationParameters.ValidateAudience = false;
        });
    builder.Services.AddAuthorization();

    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen();

    var app = builder.Build();

    app.UseSerilogRequestLogging();

    if (app.Environment.IsDevelopment())
    {
        app.UseSwagger();
        app.UseSwaggerUI();
        // Hangfire dashboard — dev only, no auth required in local
        app.UseHangfireDashboard("/hangfire");
    }

    app.UseAuthentication();
    app.UseAuthorization();

    app.MapWebhookRoutes();
    app.MapUserRoutes();
    app.MapConversationRoutes();
    app.MapJournalRoutes();
    app.MapMoodRoutes();
    app.MapCopingRoutes();
    app.MapVoiceRoutes();

    app.Run();
}
catch (Exception ex) when (ex is not HostAbortedException)
{
    Log.Fatal(ex, "Application startup failed");
}
finally
{
    Log.CloseAndFlush();
}
