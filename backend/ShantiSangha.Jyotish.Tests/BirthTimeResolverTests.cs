using ShantiSangha.Jyotish.Services;
using Xunit;

namespace ShantiSangha.Jyotish.Tests;

/// <summary>
/// Verifies BirthTimeResolver correctly maps (lat, lon, local time) → UTC
/// using IANA timezone data. This replaced the crude longitude/15 estimate
/// which was off by 4 minutes for Kathmandu (NPT is UTC+5:45, not UTC+5:41).
/// </summary>
public class BirthTimeResolverTests
{
    [Fact]
    public void Kathmandu_Returns5h45mOffset_NotLongitudeEstimate()
    {
        // Kathmandu: 27.7172°N, 85.3240°E. NPT is UTC+5:45 (no DST).
        // Longitude/15 estimate would give 5h41m — 4 minutes off.
        var localDate = new DateOnly(1990, 6, 22);
        var localTime = new TimeOnly(6, 0);
        var utc = BirthTimeResolver.ResolveBirthUtc(localDate, localTime, 27.7172, 85.3240);

        // Expect: 06:00 NPT − 5:45 = 00:15 UTC (not 00:18 as longitude/15 gives)
        var expected = new DateTime(1990, 6, 22, 0, 15, 0, DateTimeKind.Utc);
        Assert.Equal(expected, utc);
    }

    [Fact]
    public void NewYork_AppliesDST_Correctly()
    {
        // Summer birth in NYC: EDT (UTC-4). Winter birth: EST (UTC-5).
        var lat = 40.7128;
        var lon = -74.0060;

        // July 4, 1990, 12:00 EDT → 16:00 UTC
        var summerUtc = BirthTimeResolver.ResolveBirthUtc(
            new DateOnly(1990, 7, 4), new TimeOnly(12, 0), lat, lon);
        Assert.Equal(new DateTime(1990, 7, 4, 16, 0, 0, DateTimeKind.Utc), summerUtc);

        // Jan 1, 1990, 12:00 EST → 17:00 UTC
        var winterUtc = BirthTimeResolver.ResolveBirthUtc(
            new DateOnly(1990, 1, 1), new TimeOnly(12, 0), lat, lon);
        Assert.Equal(new DateTime(1990, 1, 1, 17, 0, 0, DateTimeKind.Utc), winterUtc);
    }

    [Fact]
    public void India_UsesIST_UTC5h30m()
    {
        // Delhi: 28.6139°N, 77.2090°E. IST = UTC+5:30 (no DST).
        var utc = BirthTimeResolver.ResolveBirthUtc(
            new DateOnly(2000, 6, 15), new TimeOnly(14, 30), 28.6139, 77.2090);
        Assert.Equal(new DateTime(2000, 6, 15, 9, 0, 0, DateTimeKind.Utc), utc);
    }

    [Fact]
    public void NullCoordinates_ReturnsLocalAsUtc()
    {
        // Fallback when user hasn't provided a birth place.
        var utc = BirthTimeResolver.ResolveBirthUtc(
            new DateOnly(1990, 1, 1), new TimeOnly(12, 0), null, null);
        Assert.Equal(DateTimeKind.Utc, utc.Kind);
        Assert.Equal(new DateTime(1990, 1, 1, 12, 0, 0, DateTimeKind.Utc), utc);
    }

    [Fact]
    public void Tokyo_UsesJST_UTC9()
    {
        var utc = BirthTimeResolver.ResolveBirthUtc(
            new DateOnly(1995, 3, 15), new TimeOnly(8, 0), 35.6762, 139.6503);
        Assert.Equal(new DateTime(1995, 3, 14, 23, 0, 0, DateTimeKind.Utc), utc);
    }

    [Fact]
    public void London_DST_TransitionDate()
    {
        // London: GMT in winter, BST (UTC+1) in summer.
        // July 1, 2020, 12:00 BST → 11:00 UTC
        var summerUtc = BirthTimeResolver.ResolveBirthUtc(
            new DateOnly(2020, 7, 1), new TimeOnly(12, 0), 51.5074, -0.1278);
        Assert.Equal(new DateTime(2020, 7, 1, 11, 0, 0, DateTimeKind.Utc), summerUtc);
    }
}
