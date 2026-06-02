using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.SemanticKernel;
using ShantiSangha.Agent.AI;
using ShantiSangha.Agent.Contracts;
using ShantiSangha.Shared;
using Xunit;
using Xunit.Abstractions;

namespace ShantiSangha.AiEval.Tests.Agent;

/// <summary>
/// Golden-set eval for <see cref="QuickActionSuggester"/> — the cheap second
/// pass that offers tappable follow-up chips after an assistant reply.
///
/// This is a behavioral eval, not an exact-text test: we assert WHETHER chips
/// appear (and that they're well-formed), never the specific labels. The two
/// properties that matter:
///   1. SPARSENESS — trivial / closing replies must yield ZERO chips. This is
///      the whole point; chips on every turn would make the chat noisy.
///   2. HELPFULNESS — replies with a clear next step (listed reminders, an
///      offered reminder, the circle) yield 1–3 well-formed chips.
///
/// Live (hits gpt-4o-mini); gated behind <see cref="LiveEvalFactAttribute"/>.
/// </summary>
public sealed class QuickActionSuggesterEvalTests(ITestOutputHelper output)
{
    private static QuickActionSuggester BuildSuggester()
    {
        var apiKey = Environment.GetEnvironmentVariable("OPENAI_API_KEY")!;
        var kernel = Kernel.CreateBuilder()
            .AddOpenAIChatCompletion(AiModels.FastModel, apiKey, serviceId: AiModels.FastServiceId)
            .Build();
        return new QuickActionSuggester(kernel, NullLogger<QuickActionSuggester>.Instance);
    }

    /// Closing / acknowledgement turns where there's no useful next action.
    public static IEnumerable<object[]> SparseCases =>
    [
        ["thanks!", "You're welcome, Subin. Take care."],
        ["ok sounds good", "Glad I could help. Talk soon."],
        ["that waterfall photo is just for fun", "It looks beautiful and peaceful — a lovely place to pause."],
        // Open-ended clarifying question mid-flow: the user must type the
        // detail, and re-offering "Set reminder" would be redundant.
        ["Remind me about something on January 24, 2027.", "What would you like to be reminded about on January 24, 2027? Let me know the details so I can set it up for you."],
    ];

    /// Turns with an obvious next step the user is likely to want.
    public static IEnumerable<object[]> ActionableCases =>
    [
        ["what reminders do I have this week?", "Here's what you have coming up this week:"],
        ["[Shared a photo]", "That looks like a dentist appointment on June 14. Want me to set a reminder for it?"],
        ["who's in my circle?", "Here's everyone you're keeping track of right now:"],
    ];

    [LiveEvalFact]
    public async Task ChipPromptCarriesTheSubjectNotABareVerb()
    {
        // Regression: after a shared document the chip used to send a bare
        // "Set a reminder", dropping the subject so the assistant restarted.
        // The prompt must name what it's about.
        var suggester = BuildSuggester();
        var actions = await suggester.SuggestAsync(
            "[Shared a photo]",
            "It looks like a notice of action from the U.S. Citizenship and Immigration Services (USCIS). If there's anything specific you'd like to do with this, let me know.");
        output.WriteLine($"[subject] -> {Describe(actions)}");

        Assert.NotEmpty(actions);
        var carriesSubject = actions.Any(a =>
        {
            var p = a.Prompt.ToLowerInvariant();
            return p.Contains("notice") || p.Contains("uscis") || p.Contains("immigration");
        });
        Assert.True(carriesSubject,
            $"Expected a chip whose prompt names the document; got: {Describe(actions)}");
    }

    [LiveEvalFact]
    public async Task TrivialRepliesYieldNoChips()
    {
        var suggester = BuildSuggester();
        var failures = new List<string>();

        foreach (var c in SparseCases)
        {
            var actions = await suggester.SuggestAsync((string)c[0], (string)c[1]);
            output.WriteLine($"[sparse] \"{c[1]}\" -> {Describe(actions)}");
            if (actions.Count != 0)
                failures.Add($"Expected 0 chips for \"{c[1]}\" but got {Describe(actions)}");
        }

        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    [LiveEvalFact]
    public async Task ActionableRepliesYieldWellFormedChips()
    {
        var suggester = BuildSuggester();
        var failures = new List<string>();

        foreach (var c in ActionableCases)
        {
            var actions = await suggester.SuggestAsync((string)c[0], (string)c[1]);
            output.WriteLine($"[actionable] \"{c[1]}\" -> {Describe(actions)}");

            if (actions.Count is < 1 or > 3)
                failures.Add($"Expected 1–3 chips for \"{c[1]}\" but got {actions.Count}");

            foreach (var a in actions)
            {
                if (string.IsNullOrWhiteSpace(a.Label) || a.Label.Length > 40)
                    failures.Add($"Bad label \"{a.Label}\" for \"{c[1]}\"");
                if (string.IsNullOrWhiteSpace(a.Prompt))
                    failures.Add($"Empty prompt for label \"{a.Label}\" on \"{c[1]}\"");
            }
        }

        Assert.True(failures.Count == 0, string.Join("\n", failures));
    }

    private static string Describe(IReadOnlyList<QuickAction> actions) =>
        actions.Count == 0
            ? "(none)"
            : string.Join(", ", actions.Select(a => $"[{a.Label}]"));
}
