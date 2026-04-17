using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Jyotish.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Jyotish;

public static class DependencyInjection
{
    public static IServiceCollection AddJyotishModule(this IServiceCollection services)
    {
        services.AddScoped<IJyotishContextService, JyotishContextService>();
        return services;
    }
}
