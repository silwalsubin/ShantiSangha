using ShantiSangha.Shared.AI;
using ShantiSangha.Shared.Models;
using Xunit;

namespace ShantiSangha.AiEval.Tests.Shared;

/// <summary>
/// Deterministic guards for the merged one-mind prompt
/// (<see cref="UnifiedPrompt"/>) that now backs BOTH chat surfaces. No LLM —
/// these pin the invariants the merge must not lose: the companion's warmth
/// and crisis handling, the assistant's tool discipline, and the
/// surface-specific rendering notes. CI-safe.
/// </summary>
public sealed class UnifiedPromptTests
{
    private static readonly DateOnly Today = new(2026, 8, 26);

    [Fact]
    public void BothSurfacesCarryWarmthAndToolDiscipline()
    {
        foreach (var surface in new[] { PromptSurface.Reflect, PromptSurface.Assistant })
        {
            var prompt = UnifiedPrompt.Build(Today, "Subin", memories: null, surface);

            // Companion warmth survived the merge.
            Assert.Contains("Bhagavad Gita", prompt);
            Assert.Contains("When someone is in distress", prompt);
            Assert.Contains("walk beside them", prompt);
            // Assistant hands survived the merge.
            Assert.Contains("schedule_reminder", prompt);
            Assert.Contains("ALWAYS call list_reminders", prompt);
            Assert.Contains("confirmed: true", prompt);
            Assert.Contains("report_feedback", prompt);
            // Both moments are named — the anti-tone-bleed core.
            Assert.Contains("never turn a feeling into", prompt);
            Assert.Contains("Never turn a small task into", prompt);
            // Date grounding.
            Assert.Contains("2026-08-26 (Wednesday)", prompt);
            Assert.Contains("Subin", prompt);
        }
    }

    [Fact]
    public void ReflectSurfaceNeverPointsAtCards()
    {
        var reflect = UnifiedPrompt.Build(Today, "Subin", memories: null, PromptSurface.Reflect);
        var assistant = UnifiedPrompt.Build(Today, "Subin", memories: null, PromptSurface.Assistant);

        // The Reflect chat renders prose only — the model must not gesture at
        // tappable cards that aren't there.
        Assert.DoesNotContain("tappable", reflect);
        Assert.Contains("no reminder cards are rendered", reflect);

        Assert.Contains("tappable", assistant);
        Assert.DoesNotContain("no reminder cards are rendered", assistant);
    }

    [Fact]
    public void MemoriesComeLastForPromptCaching()
    {
        const string marker = "the visa paperwork thread";
        var prompt = UnifiedPrompt.Build(Today, "Subin", marker, PromptSurface.Reflect);

        Assert.Contains("What you remember about this person", prompt);
        // Most volatile content last, so the stable prefix stays cacheable.
        Assert.True(prompt.IndexOf(marker, StringComparison.Ordinal)
                    > prompt.IndexOf("2026-08-26", StringComparison.Ordinal));
        // The block that invites reciting memories must also forbid claiming
        // no access — the assistant-side regression the old split prompt had.
        Assert.Contains("never claim you lack access", prompt);
    }

    [Fact]
    public void FormatMemoriesClipsAndLabelsSources()
    {
        var longEntry = new string('x', 1000);
        var hits = new List<MemoryHit>
        {
            new("journal", Guid.NewGuid(), longEntry, new DateTime(2026, 8, 1), 0.9),
            new("chat_message", Guid.NewGuid(), "short thought", new DateTime(2026, 8, 10), 0.8),
        };

        var formatted = UnifiedPrompt.FormatMemories(hits)!;

        Assert.Contains("[journal entry, August 1, 2026]", formatted);
        Assert.Contains("[conversation, August 10, 2026]", formatted);
        Assert.Contains("…", formatted);
        // 400-char clip plus framing — nowhere near the full 1000.
        Assert.True(formatted.Length < 950);

        Assert.Null(UnifiedPrompt.FormatMemories([]));
    }
}
