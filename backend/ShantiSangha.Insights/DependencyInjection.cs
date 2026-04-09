using Hangfire;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ShantiSangha.Insights.Data;
using ShantiSangha.Insights.Jobs;
using ShantiSangha.Insights.Models;
using ShantiSangha.Insights.Services;
using ShantiSangha.Shared.Events;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Insights;

public static class DependencyInjection
{
    public static IServiceCollection AddInsightsModule(
        this IServiceCollection services,
        string connectionString)
    {
        services.AddDbContext<InsightsDbContext>(options =>
            options.UseNpgsql(connectionString, o => o.UseVector()));

        services.AddScoped<InsightService>();
        services.AddScoped<SemanticSearchService>();
        services.AddScoped<InsightQueryService>();
        services.AddScoped<IInsightQueryService>(sp => sp.GetRequiredService<InsightQueryService>());
        services.AddScoped<SummaryQueryService>();
        services.AddScoped<ISummaryQueryService>(sp => sp.GetRequiredService<SummaryQueryService>());
        services.AddScoped<GenerateSummaryJob>();
        services.AddScoped<ExtractInsightsJob>();
        services.AddScoped<GenerateInsightEmbeddingJob>();

        return services;
    }

    public static void SubscribeInsightsEvents(this IServiceProvider services)
    {
        var eventBus = services.GetRequiredService<IEventBus>();

        eventBus.Subscribe<MessagesSavedEvent>(async (@event, ct) =>
        {
            var jobs = services.GetRequiredService<IBackgroundJobClient>();

            // Generate summary every 10 messages
            if (@event.MessageCount % 10 == 0)
            {
                var summaryJobId = jobs.Enqueue<GenerateSummaryJob>(
                    j => j.RunForConversationAsync(@event.ConversationId, @event.UserId));

                jobs.ContinueJobWith<ExtractInsightsJob>(summaryJobId,
                    j => j.RunAsync(@event.ConversationId, SummarySourceType.Conversation, @event.UserId));
            }

            await Task.CompletedTask;
        });

        eventBus.Subscribe<JournalCreatedEvent>(async (@event, ct) =>
        {
            var jobs = services.GetRequiredService<IBackgroundJobClient>();

            var summaryJobId = jobs.Enqueue<GenerateSummaryJob>(
                j => j.RunForJournalAsync(@event.JournalId, @event.UserId));

            jobs.ContinueJobWith<ExtractInsightsJob>(summaryJobId,
                j => j.RunAsync(@event.JournalId, SummarySourceType.Journal, @event.UserId));

            await Task.CompletedTask;
        });
    }
}
