using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Tools.AgentFeedback;
using ShantiSangha.Tools.Circles;
using ShantiSangha.Tools.Reminders;

namespace ShantiSangha.Tools;

public static class DependencyInjection
{
    public static IServiceCollection AddToolsModule(this IServiceCollection services)
    {
        services.AddScoped<RemindersTool>();
        services.AddScoped<CirclesTool>();
        services.AddScoped<AgentFeedbackTool>();
        services.AddScoped<RemindersListSink>();
        services.AddScoped<AgentTurnContext>();
        return services;
    }
}
