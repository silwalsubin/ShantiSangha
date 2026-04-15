using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Data;
using ShantiSangha.Wellness.Jobs;
using ShantiSangha.Wellness.Services;
using ShantiSangha.Wellness.Storage;

namespace ShantiSangha.Wellness;

public static class DependencyInjection
{
    public static IServiceCollection AddWellnessModule(
        this IServiceCollection services,
        string connectionString,
        string voiceBucketName)
    {
        services.AddDbContext<WellnessDbContext>(options =>
            options.UseNpgsql(connectionString));

        services.AddSingleton(sp =>
        {
            var logger = sp.GetRequiredService<ILogger<StorageService>>();
            var region = Environment.GetEnvironmentVariable("AWS_REGION") ?? "us-east-1";
            return new StorageService(voiceBucketName, region, logger);
        });

        services.AddScoped<IVoiceService, VoiceService>();
        services.AddScoped<GenerateDailyReflectionJob>();

        return services;
    }
}
