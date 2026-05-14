using System.ComponentModel;
using Microsoft.SemanticKernel;
using ModelContextProtocol.Server;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Tools.Reflection;

[McpServerToolType]
public sealed class ReflectionTool(IReflectionQueryService reflections, ICurrentUser currentUser)
{
    [McpServerTool(Name = "get_today_reflection")]
    [KernelFunction("get_today_reflection")]
    [Description(
        "Return the user's daily reflection — the short observation drawn from " +
        "their reminders, journal, and recent activity, generated each morning. " +
        "Use when the user asks 'what's my reflection', 'read me my reflection', " +
        "'what should I focus on today', or anything that's clearly asking for " +
        "the daily morning text. " +
        "Returns null when no reflection has been generated yet (this can happen " +
        "for brand-new users or when the overnight job hasn't completed). " +
        "If null, tell the user it's still being prepared and not to worry.")]
    public async Task<object> GetTodayReflection(CancellationToken ct = default)
    {
        var user = await RequireUserAsync();
        var text = await reflections.GetRecentReflectionAsync(user.Id, ct);

        if (string.IsNullOrWhiteSpace(text))
        {
            return new { reflection = (string?)null, message = "No reflection is ready yet." };
        }

        return new { reflection = text };
    }

    private async Task<CurrentUserInfo> RequireUserAsync()
    {
        var user = await currentUser.GetAsync();
        return user ?? throw new UnauthorizedAccessException("No authenticated user on this request.");
    }
}
