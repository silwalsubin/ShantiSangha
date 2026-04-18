using ShantiSangha.Jyotish.Services;
using Xunit;

namespace ShantiSangha.Jyotish.Tests;

/// <summary>
/// Validates PlanetaryPositions against physical constraints and reference
/// positions from established astronomical sources. These tests would have
/// caught the earlier Earth-coordinate-sign bug that put Mercury and Venus
/// on the opposite side of the zodiac from the Sun.
/// </summary>
public class PlanetaryPositionsTests
{
    /// <summary>
    /// Returns the absolute angular difference between two longitudes,
    /// measuring the shorter arc across 0°/360° wrap.
    /// </summary>
    private static double AngularDistance(double a, double b)
    {
        var diff = Math.Abs(a - b) % 360;
        return diff > 180 ? 360 - diff : diff;
    }

    // ------------------------------------------------------------------
    // Physical elongation constraints — the single most important sanity
    // check for planetary positions. Mercury can never be more than ~28°
    // from the Sun. Venus can never be more than ~48°. If this test fails,
    // the geocentric math is wrong.
    // ------------------------------------------------------------------

    [Theory]
    [InlineData(2000, 1, 1)]
    [InlineData(2005, 6, 15)]
    [InlineData(2010, 9, 22)]
    [InlineData(2015, 3, 20)]
    [InlineData(2020, 12, 21)]
    [InlineData(2024, 7, 4)]
    [InlineData(2026, 4, 18)]
    [InlineData(1990, 1, 15)]
    [InlineData(1985, 8, 8)]
    public void Mercury_IsWithin28DegreesOfSun(int year, int month, int day)
    {
        var date = new DateTime(year, month, day, 12, 0, 0, DateTimeKind.Utc);
        var sun = VedicCalendar.GetTropicalSunLongitude(date);
        var mercury = PlanetaryPositions.GetTropicalMercuryLongitude(date);

        var elongation = AngularDistance(mercury, sun);

        // Allow 30° as a tolerant upper bound (true max is ~28°, plus calc fuzz).
        Assert.True(elongation <= 30,
            $"Mercury-Sun elongation on {date:yyyy-MM-dd} was {elongation:F2}° (should be ≤ 28°). " +
            $"Sun={sun:F2}°, Mercury={mercury:F2}°.");
    }

    [Theory]
    [InlineData(2000, 1, 1)]
    [InlineData(2005, 6, 15)]
    [InlineData(2010, 9, 22)]
    [InlineData(2015, 3, 20)]
    [InlineData(2020, 12, 21)]
    [InlineData(2024, 7, 4)]
    [InlineData(2026, 4, 18)]
    [InlineData(1990, 1, 15)]
    [InlineData(1985, 8, 8)]
    public void Venus_IsWithin48DegreesOfSun(int year, int month, int day)
    {
        var date = new DateTime(year, month, day, 12, 0, 0, DateTimeKind.Utc);
        var sun = VedicCalendar.GetTropicalSunLongitude(date);
        var venus = PlanetaryPositions.GetTropicalVenusLongitude(date);

        var elongation = AngularDistance(venus, sun);

        // True max is ~47°, allow 50° tolerance.
        Assert.True(elongation <= 50,
            $"Venus-Sun elongation on {date:yyyy-MM-dd} was {elongation:F2}° (should be ≤ 48°). " +
            $"Sun={sun:F2}°, Venus={venus:F2}°.");
    }

    /// <summary>
    /// Sweep across 20 years to make sure the elongation constraints hold
    /// at every sample, not just at the hand-picked dates.
    /// </summary>
    [Fact]
    public void Mercury_Venus_ElongationHoldsOverTwoDecades()
    {
        var start = new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var end = new DateTime(2030, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        for (var d = start; d < end; d = d.AddDays(15))
        {
            var sun = VedicCalendar.GetTropicalSunLongitude(d);
            var mercury = PlanetaryPositions.GetTropicalMercuryLongitude(d);
            var venus = PlanetaryPositions.GetTropicalVenusLongitude(d);

            var mercElong = AngularDistance(mercury, sun);
            var venusElong = AngularDistance(venus, sun);

            Assert.True(mercElong <= 30, $"Mercury elongation {mercElong:F2}° on {d:yyyy-MM-dd}");
            Assert.True(venusElong <= 50, $"Venus elongation {venusElong:F2}° on {d:yyyy-MM-dd}");
        }
    }

    // ------------------------------------------------------------------
    // Rahu / Ketu — lunar nodes
    // ------------------------------------------------------------------

    [Fact]
    public void Ketu_IsExactly180DegreesFromRahu()
    {
        var date = new DateTime(2025, 6, 15, 12, 0, 0, DateTimeKind.Utc);
        var rahu = PlanetaryPositions.GetTropicalRahuLongitude(date);
        var ketu = PlanetaryPositions.GetTropicalKetuLongitude(date);

        var expected = (rahu + 180) % 360;
        Assert.Equal(expected, ketu, precision: 6);
    }

    [Fact]
    public void Rahu_RetrogradesOverTime()
    {
        // Rahu moves retrograde at ~0.053°/day (completes a cycle every ~18.6 years).
        var d1 = new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var d2 = new DateTime(2021, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var rahu1 = PlanetaryPositions.GetTropicalRahuLongitude(d1);
        var rahu2 = PlanetaryPositions.GetTropicalRahuLongitude(d2);

        // Over one year, Rahu should move backward by ~19.3° along the ecliptic
        var delta = (rahu1 - rahu2 + 360) % 360;
        Assert.InRange(delta, 18, 22);
    }

    // ------------------------------------------------------------------
    // Outer planets — known reference positions (tropical geocentric)
    // Reference values from publicly documented ephemerides. Allow 3°
    // tolerance for Schlyter's simplified formulas.
    // ------------------------------------------------------------------

    [Fact]
    public void Mars_AtJ2000_IsInAquariusNearCapricornCusp()
    {
        // J2000 (Jan 1 2000 12:00 UTC) — Mars is in Aquarius around 325° tropical.
        var date = new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var mars = PlanetaryPositions.GetTropicalMarsLongitude(date);

        Assert.InRange(mars, 320, 335);
    }

    [Fact]
    public void Jupiter_AtJ2000_IsInAriesAround25Degrees()
    {
        // J2000 — Jupiter is around 25° Aries = 25° tropical.
        var date = new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var jupiter = PlanetaryPositions.GetTropicalJupiterLongitude(date);

        Assert.InRange(jupiter, 22, 32);
    }

    [Fact]
    public void Saturn_AtJ2000_IsInTaurusAround10Degrees()
    {
        // J2000 — Saturn was in Taurus around 10° tropical (= 40° ecliptic).
        var date = new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var saturn = PlanetaryPositions.GetTropicalSaturnLongitude(date);

        Assert.InRange(saturn, 35, 45);
    }

    [Fact]
    public void OuterPlanets_MoveSlowly()
    {
        // Jupiter moves ~30° per year, Saturn ~12° per year. Mars ~180° per year.
        // Verify the direction of motion is prograde (forward) on average.
        var d1 = new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var d2 = new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Utc);

        var j1 = PlanetaryPositions.GetTropicalJupiterLongitude(d1);
        var j2 = PlanetaryPositions.GetTropicalJupiterLongitude(d2);
        var jDelta = (j2 - j1 + 360) % 360;
        Assert.InRange(jDelta, 20, 40); // ~30° forward

        var s1 = PlanetaryPositions.GetTropicalSaturnLongitude(d1);
        var s2 = PlanetaryPositions.GetTropicalSaturnLongitude(d2);
        var sDelta = (s2 - s1 + 360) % 360;
        Assert.InRange(sDelta, 8, 18); // ~12° forward
    }

    // ------------------------------------------------------------------
    // All longitudes must be in [0, 360)
    // ------------------------------------------------------------------

    [Fact]
    public void AllPlanetLongitudes_AreNormalized()
    {
        var date = new DateTime(2025, 6, 15, 12, 0, 0, DateTimeKind.Utc);
        var longitudes = new[]
        {
            PlanetaryPositions.GetTropicalMercuryLongitude(date),
            PlanetaryPositions.GetTropicalVenusLongitude(date),
            PlanetaryPositions.GetTropicalMarsLongitude(date),
            PlanetaryPositions.GetTropicalJupiterLongitude(date),
            PlanetaryPositions.GetTropicalSaturnLongitude(date),
            PlanetaryPositions.GetTropicalRahuLongitude(date),
            PlanetaryPositions.GetTropicalKetuLongitude(date)
        };

        foreach (var lon in longitudes)
        {
            Assert.InRange(lon, 0, 360);
            Assert.NotEqual(360, lon);
        }
    }

    // ------------------------------------------------------------------
    // Retrograde detection — Sun/Moon never, Rahu/Ketu not flagged
    // ------------------------------------------------------------------

    [Fact]
    public void IsRetrograde_SunAndMoon_AlwaysFalse()
    {
        // Sample several dates to confirm Sun and Moon are never flagged.
        foreach (var d in new[]
        {
            new DateTime(2024, 1, 1, 0, 0, 0, DateTimeKind.Utc),
            new DateTime(2024, 6, 15, 12, 0, 0, DateTimeKind.Utc),
            new DateTime(1990, 6, 22, 0, 15, 0, DateTimeKind.Utc)
        })
        {
            Assert.False(PlanetaryPositions.IsRetrograde("Sun", d));
            Assert.False(PlanetaryPositions.IsRetrograde("Moon", d));
        }
    }

    [Fact]
    public void IsRetrograde_RahuAndKetu_ReturnFalse()
    {
        // Nodes move retrograde by nature but we don't flag — it's their default state.
        var d = new DateTime(2024, 6, 15, 12, 0, 0, DateTimeKind.Utc);
        Assert.False(PlanetaryPositions.IsRetrograde("Rahu", d));
        Assert.False(PlanetaryPositions.IsRetrograde("Ketu", d));
    }

    [Fact]
    public void IsRetrograde_MercuryRetrograde_2024Apr15()
    {
        // Mercury was retrograde during the well-known period April 1 – April 25, 2024.
        var inRetro = new DateTime(2024, 4, 15, 12, 0, 0, DateTimeKind.Utc);
        Assert.True(PlanetaryPositions.IsRetrograde("Mercury", inRetro));

        // March 1, 2024 — before the retro period — should be direct.
        var direct = new DateTime(2024, 3, 1, 12, 0, 0, DateTimeKind.Utc);
        Assert.False(PlanetaryPositions.IsRetrograde("Mercury", direct));
    }

    [Fact]
    public void IsRetrograde_SaturnRetrograde_2024Aug()
    {
        // Saturn retrogrades annually for ~4.5 months. 2024 retro was roughly
        // June 29 – November 15. Mid-August falls squarely inside.
        var inRetro = new DateTime(2024, 8, 15, 12, 0, 0, DateTimeKind.Utc);
        Assert.True(PlanetaryPositions.IsRetrograde("Saturn", inRetro));
    }

    // ------------------------------------------------------------------
    // Combustion — planet within Parashara orb of Sun
    // ------------------------------------------------------------------

    [Fact]
    public void IsCombust_MercuryClose_FlaggedWithinOrb()
    {
        // Mercury 10° from Sun, direct → within 14° orb → combust.
        Assert.True(PlanetaryPositions.IsCombust("Mercury", 100, 90, retrograde: false));
        // 20° away → outside orb.
        Assert.False(PlanetaryPositions.IsCombust("Mercury", 110, 90, retrograde: false));
    }

    [Fact]
    public void IsCombust_RespectsRetrogradeTightening()
    {
        // Venus 9° from Sun, direct (10° orb) → combust.
        Assert.True(PlanetaryPositions.IsCombust("Venus", 99, 90, retrograde: false));
        // Same 9° separation but retrograde (8° orb) → NOT combust.
        Assert.False(PlanetaryPositions.IsCombust("Venus", 99, 90, retrograde: true));
    }

    [Fact]
    public void IsCombust_SunAndNodes_NeverCombust()
    {
        Assert.False(PlanetaryPositions.IsCombust("Sun", 90, 90, false));
        Assert.False(PlanetaryPositions.IsCombust("Rahu", 95, 90, false));
        Assert.False(PlanetaryPositions.IsCombust("Ketu", 95, 90, false));
    }

    [Fact]
    public void IsCombust_HandlesWrapAroundOrb()
    {
        // Planet at 355°, Sun at 5° — true separation is 10°, not 350°.
        Assert.True(PlanetaryPositions.IsCombust("Mercury", 355, 5, retrograde: false));
    }
}
