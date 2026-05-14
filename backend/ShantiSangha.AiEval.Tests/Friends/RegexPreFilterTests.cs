using ShantiSangha.Friends.Detection;
using Xunit;

namespace ShantiSangha.AiEval.Tests.Friends;

public class RegexPreFilterTests
{
    [Theory]
    // Positive — has both a date token and a reminder cue in proximity.
    [InlineData("Don't forget to call mom on Sunday")]
    [InlineData("Remind me to renew my passport before June")]
    [InlineData("Let's meet next Tuesday at the cafe")]
    [InlineData("Doctor appointment tomorrow at 3")]
    [InlineData("Need to pay the bill by Friday")]
    [InlineData("Make sure to grab milk on the way home tomorrow")]
    [InlineData("Mom's birthday is next week")]
    [InlineData("Deadline is May 30")]
    [InlineData("Got to ship this by Wednesday")]
    public void DetectsReminderShapedMessages(string body)
    {
        Assert.True(RegexPreFilter.LooksReminderShaped(body),
            $"Expected stage-1 match: '{body}'");
    }

    [Theory]
    // Negative — chit-chat, hypotheticals, single signals.
    //
    // Past-tense detection ("I had a meeting yesterday") is intentionally
    // left to the LLM stage 2 — the regex is a generous net since false
    // positives only cost one cheap LLM call.
    [InlineData("Lol what's up")]
    [InlineData("How are you doing today")]
    [InlineData("That movie was great")]
    [InlineData("Friday is my favorite day")]                  // date token but no cue
    [InlineData("I need this in my life")]                     // cue but no date
    [InlineData("Maybe sometime")]                             // vague
    [InlineData("")]
    [InlineData("   ")]
    public void IgnoresChitChat(string body)
    {
        Assert.False(RegexPreFilter.LooksReminderShaped(body),
            $"Expected stage-1 to skip: '{body}'");
    }

    [Fact]
    public void RejectsExtremelyLongMessages()
    {
        var massive = new string('a', 5000);
        Assert.False(RegexPreFilter.LooksReminderShaped(massive));
    }

    [Fact]
    public void RequiresDateAndCueWithinProximity()
    {
        // Date and cue exist but are in different sentences far apart —
        // shouldn't cross-match. ~30 words separates them.
        var body = "Friday I went to the store and it was busy but the produce was nice and "
                 + "I bought some apples and bananas and oranges and grapes and then went home "
                 + "but I still need to fix the sink";
        Assert.False(RegexPreFilter.LooksReminderShaped(body));
    }
}
