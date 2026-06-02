using Xunit;

namespace ShantiSangha.AiEval.Tests.Agent;

/// <summary>
/// A <see cref="FactAttribute"/> that skips unless the live-AI eval lane is
/// explicitly enabled. These tests hit the OpenAI API (real tokens, non-deterministic),
/// so they must never run in PR CI by default — set <c>AI_EVAL_LIVE=1</c> and
/// <c>OPENAI_API_KEY</c> to opt in. Skipped tests show as "skipped", not "passed",
/// so the gate is visible.
/// </summary>
public sealed class LiveEvalFactAttribute : FactAttribute
{
    public LiveEvalFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("AI_EVAL_LIVE") != "1")
        {
            Skip = "Live AI eval is gated. Set AI_EVAL_LIVE=1 and OPENAI_API_KEY to run.";
        }
        else if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("OPENAI_API_KEY")))
        {
            Skip = "OPENAI_API_KEY is not set; cannot run live AI eval.";
        }
    }
}
