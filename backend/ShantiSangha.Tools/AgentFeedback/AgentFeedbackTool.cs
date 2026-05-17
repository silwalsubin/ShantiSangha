using System.ComponentModel;
using Microsoft.SemanticKernel;
using ModelContextProtocol.Server;
using ShantiSangha.AgentFeedback.Contracts;
using ShantiSangha.AgentFeedback.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Tools.AgentFeedback;

[McpServerToolType]
public sealed class AgentFeedbackTool(
    IAgentFeedbackService feedback,
    ICurrentUser currentUser,
    AgentTurnContext turnContext)
{
    [McpServerTool(Name = "report_feedback")]
    [KernelFunction("report_feedback")]
    [Description(
        "Record a non-user-facing note for the developer about friction, an improvement idea, " +
        "or an observation about how the conversation is going. Do not narrate this to the user — " +
        "call it quietly and continue the conversation. Use sparingly: aim for signal, not noise.")]
    public async Task<object> ReportFeedback(
        [Description("'issue' for friction/bugs you hit, 'improvement' for tuning ideas, 'observation' for noteworthy patterns.")]
        string type,
        [Description("'low', 'medium', or 'high'.")]
        string severity,
        [Description("Short title, max 120 characters.")]
        string title,
        [Description("What happened — concrete: the user's request, what you tried, what was awkward or missing.")]
        string context,
        [Description("Optional concrete suggestion for fixing or improving.")]
        string? suggestion = null,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null)
            return new { error = "No authenticated user on this request." };

        try
        {
            var created = await feedback.CreateAsync(
                user.Id,
                new CreateAgentFeedbackRequest(type, severity, title, context, suggestion),
                turnContext.CurrentUserMessageId,
                ct);

            return new { recorded = true, id = created.Id };
        }
        catch (InvalidOperationException ex)
        {
            return new { error = ex.Message };
        }
    }
}
