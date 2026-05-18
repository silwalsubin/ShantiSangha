using ShantiSangha.Reminders.Contracts;
using ShantiSangha.Tools.Internal;
using Xunit;

namespace ShantiSangha.AiEval.Tests.Tools;

public class LabeledLookupTests
{
    private static ReminderResponse Make(string label, int daysOut = 1) =>
        new(
            Guid.NewGuid(),
            label,
            DateOnly.FromDateTime(DateTime.UtcNow.AddDays(daysOut)),
            "none",
            true,
            null,
            null,
            DateTime.UtcNow,
            daysOut,
            Array.Empty<ReminderCollaboratorDto>(),
            false,
            null);

    private static LookupResult<ReminderResponse> Find(IReadOnlyList<ReminderResponse> items, string label)
        => LabeledLookup.FindByLabel(items, r => r.Label, label);

    [Fact]
    public void NoneWhenListEmpty()
    {
        var result = Find(Array.Empty<ReminderResponse>(), "anything");
        Assert.Equal(LookupOutcome.None, result.Outcome);
    }

    [Fact]
    public void ExactMatchWins()
    {
        var reminders = new[]
        {
            Make("dad's birthday"),
            Make("dad's birthday party"),
        };
        var result = Find(reminders, "dad's birthday");
        Assert.Equal(LookupOutcome.Single, result.Outcome);
        Assert.Equal("dad's birthday", result.Match!.Label);
    }

    [Fact]
    public void CaseInsensitive()
    {
        var reminders = new[] { Make("Electric Bill") };
        var result = Find(reminders, "electric bill");
        Assert.Equal(LookupOutcome.Single, result.Outcome);
    }

    [Fact]
    public void SubstringMatchSingle()
    {
        var reminders = new[]
        {
            Make("Sarah's wedding"),
            Make("Mom's birthday"),
        };
        var result = Find(reminders, "wedding");
        Assert.Equal(LookupOutcome.Single, result.Outcome);
        Assert.Equal("Sarah's wedding", result.Match!.Label);
    }

    [Fact]
    public void AmbiguousReturnsCandidates()
    {
        var reminders = new[]
        {
            Make("Doctor appointment"),
            Make("Doctor follow-up"),
        };
        var result = Find(reminders, "doctor");
        Assert.Equal(LookupOutcome.Ambiguous, result.Outcome);
        Assert.Equal(2, result.Candidates.Count);
    }

    [Fact]
    public void TokenMatchWhenNoSubstring()
    {
        var reminders = new[] { Make("Pay the electric bill") };
        var result = Find(reminders, "electric pay");
        Assert.Equal(LookupOutcome.Single, result.Outcome);
    }

    [Fact]
    public void NoMatchReturnsNone()
    {
        var reminders = new[] { Make("Dad's birthday") };
        var result = Find(reminders, "anniversary");
        Assert.Equal(LookupOutcome.None, result.Outcome);
    }

    [Fact]
    public void EmptyLabelReturnsNone()
    {
        var reminders = new[] { Make("Dad's birthday") };
        var result = Find(reminders, "   ");
        Assert.Equal(LookupOutcome.None, result.Outcome);
    }

    // ── Cross-type sanity: works with any T + Func<T,string> ──

    private record Connection(string DisplayName);

    [Fact]
    public void GenericOverConnectionType()
    {
        var people = new[]
        {
            new Connection("Aarav Sharma"),
            new Connection("Aarav Patel"),
        };
        var result = LabeledLookup.FindByLabel(people, c => c.DisplayName, "Aarav");
        Assert.Equal(LookupOutcome.Ambiguous, result.Outcome);
        Assert.Equal(2, result.Candidates.Count);
    }
}
