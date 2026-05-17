using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.AgentFeedback.Data;
using ShantiSangha.AgentFeedback.Services;

namespace ShantiSangha.AgentFeedback;

public static class DependencyInjection
{
    public static IServiceCollection AddAgentFeedbackModule(
        this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<AgentFeedbackDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddScoped<IAgentFeedbackService, AgentFeedbackService>();

        return services;
    }
}
