using ShantiSangha.Tools.Internal;
using Xunit;

namespace ShantiSangha.AiEval.Tests.Tools;

public class DateParsingTests
{
    private static readonly DateOnly Today = new(2026, 5, 14);

    [Theory]
    [InlineData("today", "2026-05-14")]
    [InlineData("tomorrow", "2026-05-15")]
    [InlineData("yesterday", "2026-05-13")]
    [InlineData("in 7 days", "2026-05-21")]
    public void RelativeKeywords(string input, string expected)
    {
        var result = DateParsing.Parse(input, Today);
        Assert.Equal(DateOnly.Parse(expected), result);
    }

    [Theory]
    [InlineData("next Monday", "2026-05-18")]
    [InlineData("next Thursday", "2026-05-21")]
    [InlineData("next Friday", "2026-05-15")]
    [InlineData("this Friday", "2026-05-15")]
    public void NextAndThisDayOfWeek(string input, string expected)
    {
        var result = DateParsing.Parse(input, Today);
        Assert.Equal(DateOnly.Parse(expected), result);
    }

    [Theory]
    [InlineData("2026-06-10", "2026-06-10")]
    [InlineData("June 10 2026", "2026-06-10")]
    [InlineData("June 10, 2026", "2026-06-10")]
    [InlineData("Jun 10 2026", "2026-06-10")]
    public void AbsoluteFormats(string input, string expected)
    {
        var result = DateParsing.Parse(input, Today);
        Assert.Equal(DateOnly.Parse(expected), result);
    }

    [Fact]
    public void MonthDayPastInYearRollsForward()
    {
        var result = DateParsing.Parse("January 5", Today);
        Assert.Equal(new DateOnly(2027, 1, 5), result);
    }

    [Fact]
    public void MonthDayFutureInYearStaysCurrent()
    {
        var result = DateParsing.Parse("June 10", Today);
        Assert.Equal(new DateOnly(2026, 6, 10), result);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("not a date")]
    [InlineData("blahblahblah")]
    public void UnparseableReturnsNull(string input)
    {
        Assert.Null(DateParsing.Parse(input, Today));
    }
}
