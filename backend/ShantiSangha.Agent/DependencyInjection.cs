using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Agent.AI;
using ShantiSangha.Agent.Data;
using ShantiSangha.Tools;
using ShantiSangha.Tools.Circles;
using ShantiSangha.Tools.Reminders;

namespace ShantiSangha.Agent;

public static class DependencyInjection
{
    public static IServiceCollection AddAgentModule(
        this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<AgentDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddToolsModule();
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
            .WithTools<CirclesTool>();

        return services;
    }
}
