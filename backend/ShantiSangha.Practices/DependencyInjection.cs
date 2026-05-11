using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Practices.Data;
using ShantiSangha.Practices.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Practices;

public static class DependencyInjection
{
    public static IServiceCollection AddPracticesModule(
        this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<PracticesDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddScoped<IPracticeService, PracticeService>();
        services.AddScoped<IPracticeQueryService, PracticeQueryService>();
        services.AddScoped<IPracticeStatusQueryService, PracticeStatusQueryService>();

        return services;
    }
}
