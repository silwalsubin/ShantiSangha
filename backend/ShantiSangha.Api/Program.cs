using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;
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
using ShantiSangha.Chat;
using ShantiSangha.Chat.AI;
using ShantiSangha.Friends;
using ShantiSangha.Identity;
using ShantiSangha.Goals;
using ShantiSangha.Insights;
using ShantiSangha.Journal;
using ShantiSangha.Jyotish;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness;
using System.Net.Http.Headers;
using System.Text.Json.Serialization;
using Npgsql;

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

    // HTTP client for OpenAI moderation API
    builder.Services.AddHttpClient("OpenAI", client =>
    {
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", appConfig.OpenAiApiKey);
    });

    // Semantic Kernel + OpenAI (chat + embeddings) — cross-cutting, consumed by domain projects via DI.
    // Two chat models are registered under named service keys so each surface
    // can pick the right tier: Smart (gpt-4o) for synthesis-heavy work (chart
    // chat, chart reading), Fast (gpt-4o-mini) for short stylistic output
    // (titles, summaries, reflections, journal prompts). See Shared/AiModels.cs.
#pragma warning disable SKEXP0010
    var kernelBuilder = builder.Services.AddKernel()
        .AddOpenAIChatCompletion(AiModels.SmartModel, appConfig.OpenAiApiKey, serviceId: AiModels.SmartServiceId)
        .AddOpenAIChatCompletion(AiModels.FastModel, appConfig.OpenAiApiKey, serviceId: AiModels.FastServiceId)
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

    // Event bus — in-process pub/sub for cross-domain communication
    builder.Services.AddSingleton<IEventBus, InMemoryEventBus>();

    // Current user — scoped, lazily resolved once per request
    builder.Services.AddHttpContextAccessor();

    // ── Shared NpgsqlDataSource with pgvector support ─────────────────────
    var connStr = appConfig.DatabaseUrl;
    var vectorDataSourceBuilder = new NpgsqlDataSourceBuilder(connStr);
    vectorDataSourceBuilder.UseVector();
    var vectorDataSource = vectorDataSourceBuilder.Build();
    builder.Services.AddSingleton(vectorDataSource);

    // ── Domain module registration ──────────────────────────────────────
    // Avatars share the same S3 bucket as friend chat media — they're both
    // user-shared identity content with the same trust class. Identity owns
    // the avatar key + lifecycle on its own AvatarStorage S3 client.
    builder.Services.AddIdentityModule(connStr, appConfig.FriendsMediaBucketName);
    builder.Services.AddGoalsModule(connStr);
    builder.Services.AddChatModule(vectorDataSource);
    builder.Services.AddJournalModule(vectorDataSource);
    builder.Services.AddWellnessModule(connStr, appConfig.VoiceBucketName);
    builder.Services.AddInsightsModule(vectorDataSource);
    builder.Services.AddJyotishModule(vectorDataSource);
    builder.Services.AddFriendsModule(connStr, appConfig.FriendsMediaBucketName);

    // ── Controller discovery from domain assemblies ─────────────────────
    builder.Services.AddControllers()
        .AddApplicationPart(typeof(ShantiSangha.Identity.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Goals.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Chat.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Journal.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Wellness.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Insights.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Jyotish.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Friends.DependencyInjection).Assembly)
        .AddJsonOptions(opts =>
        {
            opts.JsonSerializerOptions.Converters.Add(new JsonStringEnumConverter());
        });

    // Hangfire — PostgreSQL-backed job queue
    builder.Services.AddHangfire(config => config
        .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
        .UseSimpleAssemblyNameTypeSerializer()
        .UseRecommendedSerializerSettings()
        .UsePostgreSqlStorage(o => o.UseNpgsqlConnection(appConfig.DatabaseUrl)));
    builder.Services.AddHangfireServer();

    // Firebase Admin — for sending push notifications via FCM
    if (FirebaseApp.DefaultInstance == null)
    {
        var firebaseCredJson = builder.Configuration["FIREBASE_SERVICE_ACCOUNT_JSON"]
            ?? Environment.GetEnvironmentVariable("FIREBASE_SERVICE_ACCOUNT_JSON");

        if (!string.IsNullOrEmpty(firebaseCredJson))
        {
            // Handle double-escaped JSON (stored as a string within a string)
            if (firebaseCredJson.StartsWith("\"") || firebaseCredJson.StartsWith("\\"))
            {
                try
                {
                    firebaseCredJson = System.Text.Json.JsonSerializer.Deserialize<string>(firebaseCredJson) ?? firebaseCredJson;
                }
                catch { /* not double-escaped, use as-is */ }
            }

            FirebaseApp.Create(new AppOptions
            {
                Credential = GoogleCredential.FromJson(firebaseCredJson),
                ProjectId = appConfig.FirebaseProjectId
            });
            Log.Information("Firebase Admin initialized with service account");
        }
        else
        {
            Log.Warning("Firebase Admin: no FIREBASE_SERVICE_ACCOUNT_JSON found, falling back to default credentials");
            FirebaseApp.Create(new AppOptions { ProjectId = appConfig.FirebaseProjectId });
        }
    }
    builder.Services.AddScoped<IPushNotificationService, ShantiSangha.Api.Services.PushNotificationService>();
    builder.Services.AddScoped<ShantiSangha.Shared.Jobs.SendPushNotificationJob>();

    // OpenTelemetry — traces and metrics
    builder.Services.AddOpenTelemetry()
        .ConfigureResource(r => r.AddService("ShantiSangha.Api"))
        .WithTracing(tracing => tracing
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation())
        .WithMetrics(metrics => metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation());

    // Auth — Firebase issues JWTs validated here
    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(opts =>
        {
            opts.Authority = $"https://securetoken.google.com/{appConfig.FirebaseProjectId}";
            opts.TokenValidationParameters.ValidateAudience = true;
            opts.TokenValidationParameters.ValidAudience = appConfig.FirebaseProjectId;
            opts.TokenValidationParameters.ValidIssuer = $"https://securetoken.google.com/{appConfig.FirebaseProjectId}";
            opts.MapInboundClaims = false;
            opts.Events = new JwtBearerEvents
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

    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen();

    var app = builder.Build();

    // ── Wire up cross-domain event subscriptions ────────────────────────
    using (var scope = app.Services.CreateScope())
    {
        scope.ServiceProvider.UseIdentityModule();
        scope.ServiceProvider.SubscribeInsightsEvents();
        scope.ServiceProvider.SubscribeJournalEvents();
    }

    // Run pending EF Core migrations on startup (safe to run on every deploy)
    using (var scope = app.Services.CreateScope())
    {
        var sp = scope.ServiceProvider;
        await sp.GetRequiredService<ShantiSangha.Identity.Data.IdentityDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Goals.Data.GoalsDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Chat.Data.ChatDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Journal.Data.JournalDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Wellness.Data.WellnessDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Insights.Data.InsightsDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Jyotish.Data.JyotishDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Friends.Data.FriendsDbContext>().Database.MigrateAsync();

        // Chat module has no EF migrations folder — schema was bootstrapped
        // pre-migration-framework. Apply lightweight additive changes via
        // idempotent SQL here until Chat gets a proper migration baseline.
        var chatDb = sp.GetRequiredService<ShantiSangha.Chat.Data.ChatDbContext>();
        await chatDb.Database.ExecuteSqlRawAsync(
            "ALTER TABLE \"Conversations\" ADD COLUMN IF NOT EXISTS \"Type\" text NOT NULL DEFAULT 'general';");

    }

    // Recurring jobs — use the DI-resolved manager since static JobStorage.Current
    // may not be initialized at app startup with some Hangfire configurations.
    using (var scope = app.Services.CreateScope())
    {
        var recurring = scope.ServiceProvider.GetRequiredService<IRecurringJobManager>();

        // Runs hourly; pre-generates daily reflections overnight in each user's
        // local timezone so first-open is instant.
        recurring.AddOrUpdate<ShantiSangha.Wellness.Jobs.ScheduleDailyReflectionsJob>(
            "pregenerate-daily-reflections",
            job => job.RunAsync(),
            "0 * * * *");

        // Runs hourly; at midnight in each user's local timezone, generates
        // today's Vedic daily reading so it's ready when they open the app.
        recurring.AddOrUpdate<ShantiSangha.Wellness.Jobs.ScheduleDailyReadingsJob>(
            "pregenerate-daily-readings",
            job => job.RunAsync(),
            "0 * * * *");

        // Runs hourly; sends today's reflection to each user's lock screen at
        // their configured reminder hour (local time).
        recurring.AddOrUpdate<ShantiSangha.Wellness.Jobs.SendMorningReflectionPushJob>(
            "morning-reflection-push",
            job => job.RunAsync(),
            "0 * * * *");
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

    // Controllers from domain projects handle all /api/* routes
    app.MapControllers();

    // Server version info (keep as minimal API — host-level concern)
    var serverGitHash = builder.Configuration["GIT_HASH"] ?? "dev";
    var serverBuildTime = builder.Configuration["BUILD_TIME"] ?? "unknown";
    app.MapGet("/api/version", () => Results.Ok(new
    {
        gitHash = serverGitHash.Length > 7 ? serverGitHash[..7] : serverGitHash,
        gitHashFull = serverGitHash,
        buildTime = serverBuildTime
    })).AllowAnonymous();

    // Debug: show JWT claims
    app.MapGet("/api/debug/claims", (HttpContext ctx) => Results.Ok(
        ctx.User.Claims.Select(c => new { c.Type, c.Value })
    )).RequireAuthorization();

    // Debug: Hangfire job stats
    app.MapGet("/api/debug/hangfire", () =>
    {
        var monitor = JobStorage.Current.GetMonitoringApi();
        var stats = monitor.GetStatistics();

        // Get recent failed jobs
        var failedJobs = monitor.FailedJobs(0, 10)
            .Select(j => new
            {
                j.Key,
                Name = j.Value.Job?.Type?.Name,
                MethodName = j.Value.Job?.Method?.Name,
                j.Value.Reason,
                j.Value.FailedAt,
                ExceptionMessage = j.Value.ExceptionMessage?.Length > 200
                    ? j.Value.ExceptionMessage[..200] : j.Value.ExceptionMessage
            });

        // Get recent succeeded jobs
        var succeededJobs = monitor.SucceededJobs(0, 10)
            .Select(j => new
            {
                j.Key,
                Name = j.Value.Job?.Type?.Name,
                MethodName = j.Value.Job?.Method?.Name,
                j.Value.SucceededAt,
                Duration = j.Value.TotalDuration
            });

        // Get enqueued jobs
        var queues = monitor.Queues();
        var enqueuedDetails = queues.Select(q => new
        {
            q.Name,
            q.Length,
            q.Fetched
        });

        // Get processing jobs
        var processingJobs = monitor.ProcessingJobs(0, 10)
            .Select(j => new
            {
                j.Key,
                Name = j.Value.Job?.Type?.Name,
                MethodName = j.Value.Job?.Method?.Name,
                j.Value.StartedAt
            });

        return Results.Ok(new
        {
            stats = new
            {
                stats.Enqueued,
                stats.Scheduled,
                stats.Processing,
                stats.Succeeded,
                stats.Failed,
                stats.Deleted,
                stats.Servers,
                stats.Recurring
            },
            queues = enqueuedDetails,
            recentSucceeded = succeededJobs,
            recentFailed = failedJobs,
            processing = processingJobs
        });
    }).RequireAuthorization();

    // Debug: Force-regenerate reflection (deletes today's reflection, then enqueues job)
    app.MapPost("/api/debug/hangfire/test-reflection", async (HttpContext ctx, IBackgroundJobClient jobs) =>
    {
        var currentUser = ctx.RequestServices.GetRequiredService<ShantiSangha.Shared.Interfaces.ICurrentUser>();
        var user = await currentUser.GetAsync();
        var userId = user!.Id;
        var utcToday = DateOnly.FromDateTime(DateTime.UtcNow);
        var yesterday = utcToday.AddDays(-1);
        var tomorrow = utcToday.AddDays(1);

        var wellnessDb = ctx.RequestServices.GetRequiredService<ShantiSangha.Wellness.Data.WellnessDbContext>();
        var existing = await wellnessDb.DailyReflections
            .Where(r => r.UserId == userId && r.Date >= yesterday && r.Date <= tomorrow)
            .ToListAsync();
        if (existing.Count > 0)
        {
            wellnessDb.DailyReflections.RemoveRange(existing);
            await wellnessDb.SaveChangesAsync();
        }

        jobs.Enqueue<ShantiSangha.Wellness.Jobs.GenerateDailyReflectionJob>(j => j.RunAsync(userId, (DateOnly?)null));
        return Results.Ok(new { triggered = "GenerateDailyReflectionJob", userId, deleted = existing.Count });
    }).RequireAuthorization();

    // Debug: Force-regenerate today's daily reading (deletes existing, re-enqueues job)
    app.MapPost("/api/debug/hangfire/test-daily-reading", async (HttpContext ctx, IBackgroundJobClient jobs) =>
    {
        var currentUser = ctx.RequestServices.GetRequiredService<ShantiSangha.Shared.Interfaces.ICurrentUser>();
        var user = await currentUser.GetAsync();
        var userId = user!.Id;
        var utcToday = DateOnly.FromDateTime(DateTime.UtcNow);
        var yesterday = utcToday.AddDays(-1);
        var tomorrow = utcToday.AddDays(1);

        var wellnessDb = ctx.RequestServices.GetRequiredService<ShantiSangha.Wellness.Data.WellnessDbContext>();
        var existing = await wellnessDb.DailyReadings
            .Where(r => r.UserId == userId && r.Date >= yesterday && r.Date <= tomorrow)
            .ToListAsync();
        if (existing.Count > 0)
        {
            wellnessDb.DailyReadings.RemoveRange(existing);
            await wellnessDb.SaveChangesAsync();
        }

        jobs.Enqueue<ShantiSangha.Wellness.Jobs.GenerateDailyReadingJob>(j => j.RunAsync(userId, (DateOnly?)null));
        return Results.Ok(new { triggered = "GenerateDailyReadingJob", userId, deleted = existing.Count });
    }).RequireAuthorization();

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
