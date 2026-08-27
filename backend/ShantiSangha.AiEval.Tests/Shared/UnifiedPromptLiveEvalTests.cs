using System.ComponentModel;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using ShantiSangha.AiEval.Tests.Agent;
using ShantiSangha.Shared;
using ShantiSangha.Shared.AI;
using Xunit;
using Xunit.Abstractions;

namespace ShantiSangha.AiEval.Tests.Shared;

/// <summary>
/// Live behavioral eval for the merged one-mind prompt — the two failure
/// modes the merge risks:
///   1. TONE BLEED — the tool roster flattening the companion's warmth: a
///      reflective message answered with markdown lists, or a feeling turned
///      into a tool call.
///   2. TASK DECAY — the warmth softening the assistant's tool discipline: a
///      direct reminder request that never reaches schedule_reminder, or
///      lands on the wrong date.
/// Uses a recording fake of the reminders plugin so tool behavior is
/// observable without a database. Live (hits gpt-4o); gated behind
/// <see cref="LiveEvalFactAttribute"/>.
/// </summary>
public sealed class UnifiedPromptLiveEvalTests(ITestOutputHelper output)
{
    private static readonly DateOnly Today = new(2026, 8, 26);

    private sealed class RecordingRemindersPlugin
    {
        public readonly List<string> Calls = [];
        public string? ScheduledDate;

        [KernelFunction("list_reminders")]
        [Description("List the user's reminders. Returns count and items.")]
        public string ListReminders(
            [Description("Only reminders shared with friends")] bool shared_only = false)
        {
            Calls.Add("list_reminders");
            return """{"count":1,"items":[{"label":"Pay rent","date":"2026-09-01","is_shared":false}]}""";
        }

        [KernelFunction("schedule_reminder")]
        [Description("Schedule a new reminder for the user on a date.")]
        public string ScheduleReminder(
            [Description("Short label for the reminder")] string label,
            [Description("Date in yyyy-MM-dd")] string date)
        {
            Calls.Add("schedule_reminder");
            ScheduledDate = date;
            return $$"""{"status":"scheduled","label":"{{label}}","date":"{{date}}"}""";
        }
    }

    private static (Kernel Kernel, RecordingRemindersPlugin Plugin) BuildKernel()
    {
        var apiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY")!;
        var kernel = Kernel.CreateBuilder()
            .AddOpenAIChatCompletion(AiModels.SmartModel, apiKey, serviceId: AiModels.SmartServiceId)
            .Build();
        var plugin = new RecordingRemindersPlugin();
        kernel.Plugins.AddFromObject(plugin, pluginName: "reminders");
        return (kernel, plugin);
    }

    private async Task<string> RunTurnAsync(Kernel kernel, PromptSurface surface, string userMessage)
    {
        var history = new ChatHistory(UnifiedPrompt.Build(Today, "Subin", memories: null, surface));
        history.AddUserMessage(userMessage);

        var settings = new OpenAIPromptExecutionSettings
        {
            FunctionChoiceBehavior = FunctionChoiceBehavior.Auto(),
        };
        var completion = kernel.GetRequiredService<IChatCompletionService>(AiModels.SmartServiceId);
        var reply = await completion.GetChatMessageContentAsync(history, settings, kernel);
        var text = reply.Content ?? "";
        output.WriteLine($"[{surface}] \"{userMessage}\"\n→ {text}\n");
        return text;
    }

    [LiveEvalFact]
    public async Task ReflectiveMessageStaysWarmAndToolFree()
    {
        var (kernel, plugin) = BuildKernel();
        var text = await RunTurnAsync(kernel, PromptSurface.Reflect,
            "I feel like I've been failing everyone around me lately. I can't shake it.");

        // A feeling must never become a tool call or a formatted list.
        Assert.Empty(plugin.Calls);
        Assert.DoesNotContain("\n- ", text);
        Assert.DoesNotContain("##", text);
        Assert.DoesNotContain("**", text);
        Assert.False(string.IsNullOrWhiteSpace(text));
    }

    [LiveEvalFact]
    public async Task DirectReminderRequestSchedulesOnTheRightDate()
    {
        var (kernel, plugin) = BuildKernel();
        var text = await RunTurnAsync(kernel, PromptSurface.Assistant,
            "remind me to pay rent on september 1");

        // Tool discipline survived the warmth: the reminder actually lands,
        // on the resolved date (today is 2026-08-26 → September 1, 2026).
        Assert.Contains("schedule_reminder", plugin.Calls);
        Assert.Equal("2026-09-01", plugin.ScheduledDate);
        Assert.False(string.IsNullOrWhiteSpace(text));
    }

    [LiveEvalFact]
    public async Task StateQuestionCallsListRemindersOnBothSurfaces()
    {
        foreach (var surface in new[] { PromptSurface.Reflect, PromptSurface.Assistant })
        {
            var (kernel, plugin) = BuildKernel();
            var text = await RunTurnAsync(kernel, surface, "what do I have coming up?");

            Assert.Contains("list_reminders", plugin.Calls);
            // Reflect renders no cards, so the reply itself must carry the
            // reminder; the assistant surface leans on cards instead.
            if (surface == PromptSurface.Reflect)
                Assert.Contains("rent", text, StringComparison.OrdinalIgnoreCase);
        }
    }
}
