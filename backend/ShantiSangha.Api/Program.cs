using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.SemanticKernel;
using Serilog;
using ShantiSangha.Api;
using ShantiSangha.Api.Routes;
using ShantiSangha.Core.Services;
using ShantiSangha.Infrastructure.AI;
using ShantiSangha.Infrastructure.Data;

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

    // Semantic Kernel + OpenAI
    builder.Services.AddKernel()
        .AddOpenAIChatCompletion("gpt-4o", appConfig.OpenAiApiKey);
    builder.Services.AddScoped<IChatService, ChatService>();

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
    }

    app.UseAuthentication();
    app.UseAuthorization();

    app.MapWebhookRoutes();
    app.MapUserRoutes();
    app.MapConversationRoutes();
    app.MapJournalRoutes();
    app.MapMoodRoutes();
    app.MapCopingRoutes();

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
