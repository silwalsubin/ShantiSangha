using System.Runtime.CompilerServices;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.SemanticKernel;
using Microsoft.SemanticKernel.ChatCompletion;
using Microsoft.SemanticKernel.Connectors.OpenAI;
using ShantiSangha.Shared;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Tools.Reminders;

namespace ShantiSangha.Agent.AI;

public class AgentOrchestrator(
    Kernel kernel,
    IServiceProvider services,
    ICurrentUser currentUser,
    IProfileQueryService profileQuery)
{
    private static readonly TimeSpan LoopTimeout = TimeSpan.FromSeconds(45);

    public async IAsyncEnumerable<string> StreamAsync(
        string userMessage,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var user = await currentUser.GetAsync()
            ?? throw new UnauthorizedAccessException("No authenticated user on this request.");

        string? displayName = null;
        try { displayName = await profileQuery.GetDisplayNameAsync(user.Id, cancellationToken); }
        catch { /* best-effort */ }

        var scopedKernel = kernel.Clone();
        scopedKernel.Plugins.AddFromObject(
            services.GetRequiredService<RemindersTool>(),
            pluginName: "reminders");

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var history = new ChatHistory(AgentSystemPrompt.Build(today, displayName));
        history.AddUserMessage(userMessage.Trim());

        var settings = new OpenAIPromptExecutionSettings
        {
            FunctionChoiceBehavior = FunctionChoiceBehavior.Auto(),
            Temperature = 0.2,
        };

        var completion = scopedKernel.GetRequiredService<IChatCompletionService>(AiModels.SmartServiceId);

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(LoopTimeout);

        await foreach (var chunk in completion.GetStreamingChatMessageContentsAsync(
            history, settings, scopedKernel, timeout.Token))
        {
            var text = chunk.Content;
            if (!string.IsNullOrEmpty(text))
                yield return text;
        }
    }
}
