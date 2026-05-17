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
using ShantiSangha.Notifications;
using ShantiSangha.Agent;
using ShantiSangha.AgentFeedback;
using ShantiSangha.Reminders;
using ShantiSangha.Shared;
using ShantiSangha.Trading;
using ShantiSangha.Shared.Interfaces;
using Yarp.ReverseProxy.Transforms;
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
    builder.Services.AddWellnessModule(connStr, appConfig.VoiceBucketName);
    builder.Services.AddFriendsModule(connStr, appConfig.FriendsMediaBucketName, appConfig.RedisUrl);
    builder.Services.AddNotificationsModule(connStr);

    // Agent: the in-app GPT-4o chat that can call backend operations as tools.
    // Same tool catalog (ShantiSangha.Tools) is also exposed externally via MCP
    // at /mcp so Claude Desktop / Cursor can connect with a Firebase JWT.
    builder.Services.AddAgentFeedbackModule(connStr);
    builder.Services.AddAgentModule(connStr);
    builder.Services.AddShantiSanghaMcp();

    if (appConfig.WisecatEnabled)
    {
        builder.Services.AddTradingModule(connStr, appConfig.WisecatFunctionName!, appConfig.IbkrGatewayBaseUrl);
    }
    else
    {
        Log.Warning("Wise Cat (Trading module) not registered: WISECAT_FUNCTION_NAME missing");
    }

    // YARP reverse proxy — exposes the IBKR Client Portal Gateway sidecar
    // at /api/ibkr-gateway/* so the user can complete the ~daily IBKR 2FA
    // login via a browser. The /api/* prefix matters: CloudFront routes
    // /api/* to the ALB; anything else falls through to the S3 origin
    // (the frontend SPA). Without /api/ the gateway URL would return
    // index.html instead of being proxied to the sidecar.
    builder.Services
        .AddReverseProxy()
        .LoadFromMemory(
            new[]
            {
                new Yarp.ReverseProxy.Configuration.RouteConfig
                {
                    RouteId = "ibkr-gateway",
                    ClusterId = "ibkr-gateway-cluster",
                    Match = new Yarp.ReverseProxy.Configuration.RouteMatch
                    {
                        Path = "/api/ibkr-gateway/{**catch-all}",
                    },
                    Transforms = new[]
                    {
                        new Dictionary<string, string> { ["PathRemovePrefix"] = "/api/ibkr-gateway" },
                    },
                },
            },
            new[]
            {
                new Yarp.ReverseProxy.Configuration.ClusterConfig
                {
                    ClusterId = "ibkr-gateway-cluster",
                    Destinations = new Dictionary<string, Yarp.ReverseProxy.Configuration.DestinationConfig>
                    {
                        ["primary"] = new()
                        {
                            Address = appConfig.IbkrGatewayBaseUrl,
                        },
                    },
                    // The gateway terminates TLS with a self-signed cert.
                    // Loopback inside the ECS task — fine to skip validation.
                    HttpClient = new Yarp.ReverseProxy.Configuration.HttpClientConfig
                    {
                        DangerousAcceptAnyServerCertificate = true,
                    },
                },
            })
        .AddTransforms(transformBuilderContext =>
        {
            // Rewrite the Location header on 3xx responses so the gateway's
            // absolute redirects (e.g. `/sso/Login`) stay inside the proxy
            // namespace (`/api/ibkr-gateway/sso/Login`). Without this the
            // browser follows /sso/Login back to the frontend SPA and the
            // IBKR login flow dies on the first redirect.
            if (transformBuilderContext.Route.RouteId != "ibkr-gateway") return;
            transformBuilderContext.AddResponseTransform(async ctx =>
            {
                await Task.CompletedTask;
                var resp = ctx.ProxyResponse;
                if (resp is null) return;
                if (!resp.Headers.TryGetValues("Location", out var locValues)) return;
                var loc = locValues.FirstOrDefault();
                if (string.IsNullOrEmpty(loc)) return;
                // Only rewrite same-origin absolute paths; full URLs (e.g.
                // sso.interactivebrokers.com) pass through untouched.
                if (!loc.StartsWith("/") || loc.StartsWith("//")) return;
                if (loc.StartsWith("/api/ibkr-gateway")) return;
                ctx.HttpContext.Response.Headers["Location"] = "/api/ibkr-gateway" + loc;
            });
        });

    // ── Controller discovery from domain assemblies ─────────────────────
    builder.Services.AddControllers()
        .AddApplicationPart(typeof(ShantiSangha.Identity.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Reminders.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Chat.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Journal.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Wellness.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Friends.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Notifications.DependencyInjection).Assembly)
        .AddApplicationPart(typeof(ShantiSangha.Trading.DependencyInjection).Assembly)
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
    }

    // Run pending EF Core migrations on startup (safe to run on every deploy)
    using (var scope = app.Services.CreateScope())
    {
        var sp = scope.ServiceProvider;
        await sp.GetRequiredService<ShantiSangha.Identity.Data.IdentityDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Reminders.Data.RemindersDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Chat.Data.ChatDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Journal.Data.JournalDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Wellness.Data.WellnessDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Friends.Data.FriendsDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Notifications.Data.NotificationsDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.Agent.Data.AgentDbContext>().Database.MigrateAsync();
        await sp.GetRequiredService<ShantiSangha.AgentFeedback.Data.AgentFeedbackDbContext>().Database.MigrateAsync();
        if (appConfig.WisecatEnabled)
        {
            await sp.GetRequiredService<ShantiSangha.Trading.Data.TradingDbContext>().Database.MigrateAsync();
        }
    }

    // Recurring jobs — use the DI-resolved manager since static JobStorage.Current
    // may not be initialized at app startup with some Hangfire configurations.
    using (var scope = app.Services.CreateScope())
    {
        var recurring = scope.ServiceProvider.GetRequiredService<IRecurringJobManager>();

        if (appConfig.WisecatEnabled)
        {
            // Wise Cat — pulls only the bars we don't already have, then
            // generates per-user astro-aware signals. Runs after US close.
            recurring.AddOrUpdate<ShantiSangha.Trading.Jobs.RefreshMarketDataJob>(
                "wisecat-refresh-market-data",
                job => job.RunAsync(),
                "15 20 * * 1-5");

            recurring.AddOrUpdate<ShantiSangha.Trading.Jobs.GenerateDailyTradingSignalsJob>(
                "wisecat-generate-signals",
                job => job.RunAsync(),
                "30 20 * * 1-5");

            // IBKR portfolio refresh — every 15 minutes during US market
            // hours (Mon–Fri 13:30–21:00 UTC ≈ 9:30am–5pm ET, slack on
            // either side for pre/post). Skips automatically when no
            // accounts are linked.
            recurring.AddOrUpdate<ShantiSangha.Trading.Jobs.IbkrPortfolioSyncJob>(
                "wisecat-ibkr-portfolio-sync",
                job => job.RunAsync(),
                "*/15 13-21 * * 1-5");

            // IBKR session keepalive — pings /tickle every minute to keep
            // the gateway's auth cookie warm. Also flips IbkrAccount.Status
            // to NeedsReauth the moment IBKR's session expires (~daily),
            // so the iOS app surfaces the "Re-link IBKR" banner without
            // waiting for the next portfolio refresh to fail.
            recurring.AddOrUpdate<ShantiSangha.Trading.Jobs.IbkrSessionKeepaliveJob>(
                "wisecat-ibkr-keepalive",
                job => job.RunAsync(),
                "* * * * *");
        }
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

    // IBKR Client Portal Gateway login proxy. Routes /api/ibkr-gateway/*
    // to the sidecar container at localhost:5000 so the user can complete
    // the daily IBKR 2FA login via a browser.
    //
    // TODO(auth): the proxy is publicly reachable. Defensible for a
    // single-user app because the IBKR login itself is the real auth
    // gate (no one without IBKR credentials can do anything), but in a
    // multi-user world we'd want a launcher endpoint that converts the
    // iOS Bearer token into a short-lived cookie before redirecting here.
    app.MapReverseProxy();

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

    // Debug: Force-regenerate today's trading signals for every held
    // ticker across every user. Useful right after a Lambda model upgrade —
    // the existing Hangfire schedule only fires Mon–Fri 20:15 UTC, so a
    // model deployed on a Friday won't reach holdings until Monday
    // evening unless this is triggered manually.
    app.MapPost("/api/debug/hangfire/regenerate-trading-signals",
        (IBackgroundJobClient jobs) =>
    {
        jobs.Enqueue<ShantiSangha.Trading.Jobs.GenerateDailyTradingSignalsJob>(j => j.RunAsync());
        return Results.Ok(new { triggered = "GenerateDailyTradingSignalsJob" });
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
