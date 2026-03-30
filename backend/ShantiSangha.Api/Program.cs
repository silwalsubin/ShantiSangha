using Hangfire;
using Hangfire.PostgreSql;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.SemanticKernel;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using Serilog;
using ShantiSangha.Api;
using ShantiSangha.Api.Routes;
using ShantiSangha.Api.Services;
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
    var kernelBuilder = builder.Services.AddKernel()
        .AddOpenAIChatCompletion("gpt-4o", appConfig.OpenAiApiKey)
        .AddOpenAIEmbeddingGenerator("text-embedding-3-small", appConfig.OpenAiApiKey);
#pragma warning restore SKEXP0010

    // Langfuse AI observability filter — optional, best-effort
    if (appConfig.LangfuseEnabled)
    {
        kernelBuilder.Services.AddSingleton<IFunctionInvocationFilter>(sp =>
            new LangfuseFilter(
                sp.GetRequiredService<IHttpClientFactory>(),
                appConfig.LangfusePublicKey!,
                appConfig.LangfuseSecretKey!,
                appConfig.LangfuseBaseUrl,
                sp.GetRequiredService<ILogger<LangfuseFilter>>()));
        Log.Information("Langfuse AI tracing enabled");
    }

    // Safety + Chat + Semantic Search services
    builder.Services.AddScoped<ISafetyService, SafetyService>();
    builder.Services.AddScoped<ISemanticSearchService, SemanticSearchService>();
    builder.Services.AddScoped<IChatService, ChatService>();

    // Current user — scoped, lazily resolved once per request
    builder.Services.AddHttpContextAccessor();
    builder.Services.AddScoped<ICurrentUser, CurrentUserService>();

    // AWS S3 voice storage — credentials come from ECS task role (no keys needed)
    builder.Services.AddSingleton(sp =>
    {
        var cfg = sp.GetRequiredService<AppConfig>();
        var log = sp.GetRequiredService<ILogger<StorageService>>();
        var region = builder.Configuration["AWS_REGION"] ?? "us-east-1";
        return new StorageService(cfg.VoiceBucketName, region, log);
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

    // OpenTelemetry — traces and metrics
    builder.Services.AddOpenTelemetry()
        .ConfigureResource(r => r.AddService("ShantiSangha.Api"))
        .WithTracing(tracing => tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation())
        .WithMetrics(metrics => metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation());

    // Auth — Clerk issues standard JWTs validated here
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(opts =>
        {
            opts.Authority = appConfig.ClerkAuthority;
            opts.TokenValidationParameters.ValidateAudience = false;
            opts.MapInboundClaims = false;
            opts.Events = new Microsoft.AspNetCore.Authentication.JwtBearer.JwtBearerEvents
            {
                OnAuthenticationFailed = context =>
                {
                    Log.Error(context.Exception, "JWT auth failed for {Path}: {Message}",
                        context.Request.Path, context.Exception.Message);
                    return Task.CompletedTask;
                },
            };
        });
    builder.Services.AddAuthorization();

    // CORS — allow frontend origin
    var frontendOrigin = builder.Configuration["FRONTEND_ORIGIN"] ?? "https://shantisangha.org";
    builder.Services.AddCors(options =>
    {
        options.AddDefaultPolicy(policy =>
        {
            policy.WithOrigins(frontendOrigin.Split(','))
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials();
        });
    });

    // JSON — accept string enum values from frontend (e.g. "Recurring" instead of 0)
    builder.Services.ConfigureHttpJsonOptions(opts =>
    {
        opts.SerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
    });

    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen();

    var app = builder.Build();

    // Run pending EF Core migrations on startup (safe to run on every deploy)
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.MigrateAsync();
    }

    // Global error handler — returns full error details when EXPOSE_ERRORS=true
    if (appConfig.ExposeErrors)
    {
        Log.Warning("EXPOSE_ERRORS is enabled — error details will be returned in API responses");
        app.Use(async (context, next) =>
        {
            try
            {
                await next();
            }
            catch (Exception ex)
            {
                Log.Error(ex, "Unhandled exception on {Method} {Path}", context.Request.Method, context.Request.Path);
                context.Response.StatusCode = 500;
                context.Response.ContentType = "application/json";
                await context.Response.WriteAsJsonAsync(new
                {
                    error = ex.Message,
                    type = ex.GetType().Name,
                    stackTrace = ex.StackTrace,
                    inner = ex.InnerException?.Message
                });
            }
        });
    }

    app.UseSerilogRequestLogging();
    app.UseCors();

    if (app.Environment.IsDevelopment())
    {
        app.UseSwagger();
        app.UseSwaggerUI();
        app.UseHangfireDashboard("/hangfire");
    }

    app.UseAuthentication();
    app.UseAuthorization();

    // All API routes under /api prefix
    var api = app.MapGroup("/api");
    api.MapWebhookRoutes();
    api.MapUserRoutes();
    api.MapConversationRoutes();
    api.MapJournalRoutes();
    api.MapMoodRoutes();
    api.MapCopingRoutes();
    api.MapVoiceRoutes();
    api.MapInsightRoutes();
    api.MapSearchRoutes();
    api.MapGoalRoutes();

    // Server version info
    var serverGitHash = builder.Configuration["GIT_HASH"] ?? "dev";
    var serverBuildTime = builder.Configuration["BUILD_TIME"] ?? "unknown";
    api.MapGet("/version", () => Results.Ok(new
    {
        gitHash = serverGitHash.Length > 7 ? serverGitHash[..7] : serverGitHash,
        gitHashFull = serverGitHash,
        buildTime = serverBuildTime
    })).AllowAnonymous();

    // Debug: show JWT claims (temporary — remove after debugging)
    api.MapGet("/debug/claims", (HttpContext ctx) => Results.Ok(
        ctx.User.Claims.Select(c => new { c.Type, c.Value })
    )).RequireAuthorization();

    // Health check at root (no /api prefix)
    app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }))
        .AllowAnonymous();

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
