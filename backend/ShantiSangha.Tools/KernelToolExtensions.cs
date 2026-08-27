using Microsoft.Extensions.DependencyInjection;
using Microsoft.SemanticKernel;
using ShantiSangha.Tools.AgentFeedback;
using ShantiSangha.Tools.Circles;
using ShantiSangha.Tools.Reminders;

namespace ShantiSangha.Tools;

public static class KernelToolExtensions
{
    /// <summary>
    /// The one tool roster behind every AI surface: a per-request clone of the
    /// base kernel with the reminders, circles, and feedback plugins attached
    /// (tool instances resolved from the request's DI scope, so they carry the
    /// current user).
    /// </summary>
    public static Kernel CloneWithShantiSanghaTools(this Kernel kernel, IServiceProvider services)
    {
        var scoped = kernel.Clone();
        scoped.Plugins.AddFromObject(
            services.GetRequiredService<RemindersTool>(),
            pluginName: "reminders");
        scoped.Plugins.AddFromObject(
            services.GetRequiredService<CirclesTool>(),
            pluginName: "circles");
        scoped.Plugins.AddFromObject(
            services.GetRequiredService<AgentFeedbackTool>(),
            pluginName: "agent_feedback");
        return scoped;
    }
}
