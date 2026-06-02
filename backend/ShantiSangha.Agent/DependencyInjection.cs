using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ShantiSangha.Agent.AI;
using ShantiSangha.Agent.Data;
using ShantiSangha.Agent.Storage;
using ShantiSangha.Tools;
using ShantiSangha.Tools.AgentFeedback;
using ShantiSangha.Tools.Circles;
using ShantiSangha.Tools.Reminders;

namespace ShantiSangha.Agent;

public static class DependencyInjection
{
    public static IServiceCollection AddAgentModule(
        this IServiceCollection services, string connectionString, string mediaBucketName)
    {
        services.AddDbContext<AgentDbContext>(options =>
            options.UseNpgsql(connectionString));

        // Server-side image store for photos the user shares with the
        // assistant. Reuses the shared media bucket under an `agent/` prefix.
        services.AddSingleton(sp =>
        {
            var logger = sp.GetRequiredService<ILogger<AgentMediaStorage>>();
            var region = Environment.GetEnvironmentVariable("AWS_REGION") ?? "us-east-1";
            return new AgentMediaStorage(mediaBucketName, region, logger);
        });

        services.AddToolsModule();
        services.AddScoped<QuickActionSuggester>();
        services.AddScoped<AgentOrchestrator>();
        return services;
    }

    /// <summary>
    /// Registers the same tool catalog with the MCP SDK so external clients
    /// (Claude Desktop, Cursor) see the identical surface as the in-app agent.
    /// </summary>
    public static IServiceCollection AddShantiSanghaMcp(this IServiceCollection services)
    {
        services
            .AddMcpServer()
            .WithHttpTransport()
            .WithTools<RemindersTool>()
            .WithTools<CirclesTool>()
            .WithTools<AgentFeedbackTool>();

        return services;
    }
}
