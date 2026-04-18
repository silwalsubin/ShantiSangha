using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Jyotish.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Jyotish;

public static class DependencyInjection
{
    public static IServiceCollection AddJyotishModule(this IServiceCollection services)
    {
        services.AddScoped<IJyotishContextService, JyotishContextService>();
        // Knowledge corpus is stateless — singleton so JSON loads once per process.
        services.AddSingleton<IJyotishKnowledgeService, JyotishKnowledgeService>();
        return services;
    }
}
