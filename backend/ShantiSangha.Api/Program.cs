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
using ShantiSangha.Friends.Realtime;
using ShantiSangha.Identity;
using ShantiSangha.Journal;
using ShantiSangha.Memory;
using ShantiSangha.Notifications;
using ShantiSangha.Agent;
using ShantiSangha.AgentFeedback;
using ShantiSangha.Reminders;
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
    // (titles, summaries, journal prompts). See Shared/AiModels.cs.
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
    builder.Services.AddRemindersModule(connStr);
    builder.Services.AddChatModule(vectorDataSource);
    builder.Services.AddJournalModule(vectorDataSource);
    builder.Services.AddMemoryModule(vectorDataSource);
    builder.Services.AddWellnessModule(connStr, appConfig.VoiceBucketName);
    builder.Services.AddFriendsModule(connStr, appConfig.FriendsMediaBucketName, appConfig.RedisUrl);
    builder.Services.AddNotificationsModule(connStr);

    // Agent: the in-app GPT-4o chat that can call backend operations as tools.
    // Same tool catalog (ShantiSangha.Tools) is also exposed externally via MCP
    // at /mcp so Claude Desktop / Cursor can connect with a Firebase JWT.
    builder.Services.AddAgentFeedbackModule(connStr);
    builder.Services.AddAgentModule(appConfig.FriendsMediaBucketName);
    builder.Services.AddShantiSanghaMcp();

    // ── Controller discovery from domain assemblies ─────────────────────
    builder.Services.AddControllers()
        .AddApplicationPart(typeof(ShantiSangha.Identity.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Reminders.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Chat.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Journal.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Memory.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Wellness.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Friends.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Notifications.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Agent.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.AgentFeedback.DependencyInjection).Assembly)
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
            // Falling back to default credentials means FCM sends will fail
            // silently in prod (ECS task identity has no FCM permissions).
            // Log loudly so the failure mode is grep-able instead of being
            // mistaken for an iOS-side token problem.
            Log.Error("Firebase Admin: FIREBASE_SERVICE_ACCOUNT_JSON is missing — push notifications WILL NOT be delivered. Set firebase_service_account_json in terraform.tfvars.");
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
                // The WebSocket upgrade handshake doesn't let clients set
                // arbitrary headers, so the realtime chat socket passes
                // its bearer token via `?token=...`. Lifted here so the
                // standard JWT middleware authenticates the request.
                OnMessageReceived = context =>
                {
                    var path = context.Request.Path;
                    if (path.StartsWithSegments("/api/chat/realtime"))
                    {
                        var token = context.Request.Query["token"].ToString();
                        if (!string.IsNullOrEmpty(token))
                        {
                            context.Token = token;
                        }
                    }
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
        scope.ServiceProvider.SubscribeJournalEvents();
        scope.ServiceProvider.SubscribeChatEvents();
        scope.ServiceProvider.SubscribeMemoryEvents();
    }

    // Run pending EF Core migrations on startup (safe to run on every deploy)
    using (var scope = app.Services.CreateScope())
    {
        var sp = scope.ServiceProvider;
        await sp.GetRequiredService<ShantiSangha.Identity.Data.IdentityDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Reminders.Data.RemindersDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Chat.Data.ChatDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Journal.Data.JournalDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Memory.Data.MemoryDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Wellness.Data.WellnessDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Friends.Data.FriendsDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Notifications.Data.NotificationsDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.AgentFeedback.Data.AgentFeedbackDbContext>().Database.MigrateAsync();

        // ── Unified conversation store (2026-08) ────────────────────────
        // Chat has no EF migrations baseline (tables predate the modular
        // split), so its schema evolves via idempotent SQL here: metadata
        // column + indexes for the assistant's threads.
        await sp.GetRequiredService<ShantiSangha.Chat.Data.ChatDbContext>().Database.ExecuteSqlRawAsync(
            """
            ALTER TABLE "Messages" ADD COLUMN IF NOT EXISTS "MetadataJson" text NULL;
            CREATE INDEX IF NOT EXISTS "IX_Messages_ConversationId_CreatedAt"
                ON "Messages" ("ConversationId", "CreatedAt");
            CREATE INDEX IF NOT EXISTS "IX_Conversations_UserId"
                ON "Conversations" ("UserId");
            """);

        // One-off cleanup (2026-08): the AgentMessages → unified-store
        // backfill ran in prod, so the legacy table (kept as a safety net)
        // and its EF migration history can go. Guarded: if the table still
        // holds rows but no assistant thread exists, the backfill never ran
        // — keep the table and log instead of destroying history. Safe to
        // delete this block after it has run in prod once.
        await sp.GetRequiredService<ShantiSangha.Chat.Data.ChatDbContext>().Database.ExecuteSqlRawAsync(
            """
            DO $$
            BEGIN
                IF to_regclass('"AgentMessages"') IS NOT NULL THEN
                    IF EXISTS (SELECT 1 FROM "AgentMessages")
                       AND NOT EXISTS (SELECT 1 FROM "Conversations" WHERE "Type" = 'assistant') THEN
                        RAISE WARNING 'AgentMessages has rows but no assistant conversations exist — skipping drop';
                    ELSE
                        DROP TABLE "AgentMessages";
                    END IF;
                END IF;
            END $$;
            DELETE FROM "__EFMigrationsHistory" WHERE "MigrationId" IN
                ('20260514142509_InitAgent',
                 '20260514164755_AddAgentMessageAttachments',
                 '20260602182350_AddAgentMessageImageObjectKey');
            """);
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

    // WebSocket middleware — required before any endpoint that calls
    // `context.WebSockets.AcceptWebSocketAsync()`.
    app.UseWebSockets();

    // Controllers from domain projects handle all /api/* routes
    app.MapControllers();

    // Realtime chat WebSocket — auth + membership handled inside.
    app.MapChatRealtime();

    // MCP server — same tool catalog as the in-app /api/agent/chat surface.
    // External clients (Claude Desktop, Cursor) connect here with a Firebase JWT.
    app.MapMcp("/mcp").RequireAuthorization();

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
