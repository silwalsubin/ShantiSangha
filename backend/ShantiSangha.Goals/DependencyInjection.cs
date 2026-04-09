using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Goals.Data;
using ShantiSangha.Goals.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Goals;

public static class DependencyInjection
{
    public static IServiceCollection AddGoalsModule(
        this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<GoalsDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddScoped<IGoalService, GoalService>();
        services.AddScoped<IGoalQueryService, GoalQueryService>();

        return services;
    }
}
