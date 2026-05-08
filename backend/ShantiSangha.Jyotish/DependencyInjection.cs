using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using ShantiSangha.Jyotish.Data;
using ShantiSangha.Jyotish.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Jyotish;

public static class DependencyInjection
{
    public static IServiceCollection AddJyotishModule(
        this IServiceCollection services,
        NpgsqlDataSource dataSource)
    {
        services.AddDbContext<JyotishDbContext>(options =>
            options.UseNpgsql(dataSource, o => o.UseVector()));

        services.AddScoped<IJyotishContextService, JyotishContextService>();
        services.AddScoped<JyotishKnowledgeService>();
        services.AddScoped<IJyotishKnowledgeService>(sp =>
            sp.GetRequiredService<JyotishKnowledgeService>());
        services.AddScoped<IChartReadingService, ChartReadingService>();
        services.AddScoped<IPairChartReadingService, PairChartReadingService>();
        return services;
    }
}
