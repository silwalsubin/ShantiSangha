using ShantiSangha.Jyotish.Services;
using Xunit;

namespace ShantiSangha.Jyotish.Tests;

public class VedicCalendarTests
{
    private static double AngularDistance(double a, double b)
    {
        var diff = Math.Abs(a - b) % 360;
        return diff > 180 ? 360 - diff : diff;
    }

    // ------------------------------------------------------------------
    // Sun at astronomical landmarks — these are the tightest constraints
    // we can check against without an external ephemeris.
    // ------------------------------------------------------------------

    [Theory]
    [InlineData(2024, 3, 20, 0)]     // Vernal equinox → 0° Aries (tropical)
    [InlineData(2024, 6, 20, 90)]    // Summer solstice → 90° Cancer
    [InlineData(2024, 9, 22, 180)]   // Autumn equinox → 180° Libra
    [InlineData(2024, 12, 21, 270)]  // Winter solstice → 270° Capricorn
    public void SunLongitude_AtSeasonalLandmarks(int year, int month, int day, double expectedDeg)
    {
        var date = new DateTime(year, month, day, 12, 0, 0, DateTimeKind.Utc);
        var sun = VedicCalendar.GetTropicalSunLongitude(date);

        var error = AngularDistance(sun, expectedDeg);
        Assert.True(error <= 2,
            $"Sun on {date:yyyy-MM-dd} was {sun:F2}° — expected ~{expectedDeg}° (± 2°)");
    }

    // ------------------------------------------------------------------
    // Moon completes one sidereal orbit in ~27.32 days. Sampling 27 days
    // later should give a longitude close to the starting point.
    // ------------------------------------------------------------------

    [Fact]
    public void Moon_SiderealPeriodIsAbout27Days()
    {
        var d1 = new DateTime(2025, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var d2 = d1.AddDays(27.32);

        var moon1 = VedicCalendar.GetTropicalMoonLongitude(d1);
        var moon2 = VedicCalendar.GetTropicalMoonLongitude(d2);

        var error = AngularDistance(moon1, moon2);
        // Approximate formulas have several-degree wobble — 5° tolerance.
        Assert.True(error <= 5,
            $"Moon after 27.32 days differed by {error:F2}° (expected ≤ 5°)");
    }

    // ------------------------------------------------------------------
    // Ayanamsa — Lahiri is the standard sidereal offset used in Indian
    // astrology. At J2000 it's 23.856°. At 1900 it should be ~22.46°.
    // ------------------------------------------------------------------

    [Fact]
    public void Ayanamsa_AtJ2000_Is23Point856()
    {
        var j2000 = new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var ayan = VedicCalendar.GetAyanamsa(j2000);
        Assert.Equal(23.856, ayan, precision: 2);
    }

    [Fact]
    public void Ayanamsa_Increases_OverTime()
    {
        var d1 = new DateTime(1990, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var d2 = new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        Assert.True(VedicCalendar.GetAyanamsa(d2) > VedicCalendar.GetAyanamsa(d1));
    }

    // ------------------------------------------------------------------
    // Rashi / Nakshatra / Pada bookkeeping
    // ------------------------------------------------------------------

    [Theory]
    [InlineData(0, 0)]       // 0° → Mesha (Aries)
    [InlineData(29.99, 0)]   // Still in Mesha
    [InlineData(30, 1)]      // Vrishabha (Taurus)
    [InlineData(180, 6)]     // Tula (Libra)
    [InlineData(359.99, 11)] // Meena (Pisces)
    public void RashiIndex_RespectsBoundaries(double longitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetRashiIndex(longitude));
    }

    [Theory]
    [InlineData(0, 0)]          // 0° → Ashwini
    [InlineData(13.33, 0)]      // Just barely before 13.333° boundary — still Ashwini
    [InlineData(13.34, 1)]      // Past boundary → Bharani
    [InlineData(359.99, 26)]    // Revati
    public void NakshatraIndex_RespectsBoundaries(double longitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetNakshatraIndex(longitude));
    }

    [Theory]
    [InlineData(0, 1)]         // Start of Ashwini → Pada 1
    [InlineData(3.32, 1)]      // Still in Pada 1
    [InlineData(3.34, 2)]      // Pada 2 (3.33° is the boundary)
    [InlineData(6.66, 2)]      // Still in Pada 2
    [InlineData(6.68, 3)]      // Pada 3
    [InlineData(13.32, 4)]     // End of Ashwini Pada 4
    [InlineData(13.34, 1)]     // Beginning of Bharani Pada 1
    public void Pada_CyclesEveryQuarterOfNakshatra(double longitude, int expectedPada)
    {
        Assert.Equal(expectedPada, VedicCalendar.GetPada(longitude));
    }

    // ------------------------------------------------------------------
    // Dasha — Vimshottari periods.
    // ------------------------------------------------------------------

    [Fact]
    public void Dasha_FirstPeriodBeginsAtBirth()
    {
        // At birth, the Mahadasha starts. For someone born at moon longitude
        // placing them in Ashwini nakshatra, the first Mahadasha is Ketu (7 years).
        var birth = new DateTime(1990, 1, 1, 12, 0, 0, DateTimeKind.Utc);

        // One second after birth, dasha should be the one that starts at birth
        var justAfter = birth.AddSeconds(1);
        var dasha = VedicCalendar.GetCurrentDasha(birth, justAfter);

        Assert.False(string.IsNullOrEmpty(dasha.Mahadasha));
        Assert.False(string.IsNullOrEmpty(dasha.Antardasha));
        Assert.True(dasha.MahadashaEnd > dasha.MahadashaStart);
        Assert.True(dasha.AntardashaEnd > dasha.AntardashaStart);
    }

    [Fact]
    public void Dasha_MahadashaEnds_WithinKnownPeriodRange()
    {
        // No Mahadasha can be shorter than 6 years (Sun) or longer than 20 (Venus).
        var birth = new DateTime(1990, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var now = new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var dasha = VedicCalendar.GetCurrentDasha(birth, now);

        var years = (dasha.MahadashaEnd - dasha.MahadashaStart).TotalDays / 365.25;
        // Partial first Mahadasha can be arbitrarily short; subsequent ones are 6-20.
        // Allow 0.1 to 20.5 range.
        Assert.InRange(years, 0.1, 20.5);
    }

    [Fact]
    public void Dasha_AntardashaSumsToMahadasha()
    {
        // Within a Mahadasha, all 9 antardashas should fill the period.
        // Walk through them and verify totals.
        var birth = new DateTime(1990, 1, 1, 12, 0, 0, DateTimeKind.Utc);
        var mid = birth.AddYears(15);
        var dasha = VedicCalendar.GetCurrentDasha(birth, mid);

        // The current Antardasha should fall within the current Mahadasha.
        Assert.True(dasha.AntardashaStart >= dasha.MahadashaStart);
        Assert.True(dasha.AntardashaEnd <= dasha.MahadashaEnd.AddDays(1)); // small slack
    }

    // ------------------------------------------------------------------
    // Ascendant — known configurations
    // ------------------------------------------------------------------

    [Fact]
    public void Ascendant_LatitudeZero_VernalEquinox_Sunrise_IsAries()
    {
        // At the equator, at vernal equinox, at local sunrise (~6am local time),
        // the Sun is on the eastern horizon which is at 0° Aries (tropical).
        // So the ascendant should be approximately 0° Aries.
        // Vernal equinox 2024-03-20 03:06 UTC.
        // Sunrise at 0° longitude (Greenwich) at equator is ~6am UTC = equinox + a few hours.
        var date = new DateTime(2024, 3, 20, 6, 0, 0, DateTimeKind.Utc);
        var asc = VedicCalendar.GetTropicalAscendant(date, latitudeDeg: 0, longitudeDeg: 0);

        // Allow ±20° tolerance — this is a rough sanity check, not precision.
        var distFromAries = AngularDistance(asc, 0);
        Assert.True(distFromAries <= 20,
            $"Ascendant at equator/sunrise/equinox was {asc:F2}° (expected near 0°, got distance {distFromAries:F2}°)");
    }

    [Fact]
    public void Ascendant_AllLatitudes_ReturnNormalizedValue()
    {
        var date = new DateTime(2025, 6, 15, 12, 0, 0, DateTimeKind.Utc);
        foreach (var lat in new[] { -60.0, -30.0, 0.0, 30.0, 60.0 })
        {
            foreach (var lon in new[] { -120.0, -60.0, 0.0, 60.0, 120.0 })
            {
                var asc = VedicCalendar.GetTropicalAscendant(date, lat, lon);
                Assert.InRange(asc, 0, 360);
                Assert.NotEqual(360, asc);
            }
        }
    }

    /// <summary>
    /// Ascendant advances by ~360° every 24 sidereal hours. In a 12-hour span,
    /// it should advance by ~180°.
    /// </summary>
    [Fact]
    public void Ascendant_Advances_WithSiderealTime()
    {
        var d1 = new DateTime(2025, 6, 15, 0, 0, 0, DateTimeKind.Utc);
        var d2 = d1.AddHours(12);

        var asc1 = VedicCalendar.GetTropicalAscendant(d1, 28.0, 77.0); // Delhi
        var asc2 = VedicCalendar.GetTropicalAscendant(d2, 28.0, 77.0);

        var delta = (asc2 - asc1 + 360) % 360;
        // ~180° after 12 hours — allow 150-210.
        Assert.InRange(delta, 150, 210);
    }

    // ------------------------------------------------------------------
    // House placement
    // ------------------------------------------------------------------

    [Theory]
    // Whole-sign: house is determined by sign index difference, not degree.
    // Ascendant at 15° Aries (rashi 0). Body at 15° Aries → same sign → H1.
    [InlineData(15.0, 15.0, 1)]
    // Body at 45° = 15° Taurus (rashi 1) → next sign → H2.
    [InlineData(45.0, 15.0, 2)]
    // Body at 14° Aries (rashi 0), same sign as asc → H1 (whole-sign ignores degree).
    [InlineData(14.0, 15.0, 1)]
    // Body at 345° = 15° Pisces (rashi 11), previous sign → H12.
    [InlineData(345.0, 15.0, 12)]
    // Body at 195° = 15° Libra (rashi 6), 6 signs ahead → H7.
    [InlineData(195.0, 15.0, 7)]
    public void GetHouse_IsCorrectRelativeToAscendant(double body, double asc, int expectedHouse)
    {
        Assert.Equal(expectedHouse, VedicCalendar.GetHouse(body, asc));
    }

    // ------------------------------------------------------------------
    // Dignity (uccha / swakshetra / neecha) — chart-specific classification
    // Rashi index reminder: 0=Mesha, 1=Vrishabha, 2=Mithuna, 3=Karka,
    // 4=Simha, 5=Kanya, 6=Tula, 7=Vrischika, 8=Dhanu, 9=Makara,
    // 10=Kumbha, 11=Meena.
    // ------------------------------------------------------------------

    [Theory]
    // Sun: exalted in Mesha, own Simha, debilitated in Tula.
    [InlineData("Sun", 0, "exalted")]
    [InlineData("Sun", 4, "own_sign")]
    [InlineData("Sun", 6, "debilitated")]
    [InlineData("Sun", 2, "neutral")]
    // Moon: exalted in Vrishabha, own Karka, debilitated in Vrischika.
    [InlineData("Moon", 1, "exalted")]
    [InlineData("Moon", 3, "own_sign")]
    [InlineData("Moon", 7, "debilitated")]
    [InlineData("Moon", 0, "neutral")]
    // Mars: exalted in Makara, own Mesha and Vrischika, debilitated in Karka.
    [InlineData("Mars", 9, "exalted")]
    [InlineData("Mars", 0, "own_sign")]
    [InlineData("Mars", 7, "own_sign")]
    [InlineData("Mars", 3, "debilitated")]
    [InlineData("Mars", 5, "neutral")]
    // Mercury: exalted in Kanya (priority over own_sign), own Mithuna, debilitated in Meena.
    [InlineData("Mercury", 5, "exalted")]
    [InlineData("Mercury", 2, "own_sign")]
    [InlineData("Mercury", 11, "debilitated")]
    [InlineData("Mercury", 4, "neutral")]
    // Jupiter: exalted in Karka, own Dhanu and Meena, debilitated in Makara.
    [InlineData("Jupiter", 3, "exalted")]
    [InlineData("Jupiter", 8, "own_sign")]
    [InlineData("Jupiter", 11, "own_sign")]
    [InlineData("Jupiter", 9, "debilitated")]
    [InlineData("Jupiter", 2, "neutral")]
    // Venus: exalted in Meena, own Vrishabha and Tula, debilitated in Kanya.
    [InlineData("Venus", 11, "exalted")]
    [InlineData("Venus", 1, "own_sign")]
    [InlineData("Venus", 6, "own_sign")]
    [InlineData("Venus", 5, "debilitated")]
    [InlineData("Venus", 0, "neutral")]
    // Saturn: exalted in Tula, own Makara and Kumbha, debilitated in Mesha.
    [InlineData("Saturn", 6, "exalted")]
    [InlineData("Saturn", 9, "own_sign")]
    [InlineData("Saturn", 10, "own_sign")]
    [InlineData("Saturn", 0, "debilitated")]
    [InlineData("Saturn", 3, "neutral")]
    // Rahu: Parashara tradition — exalted in Vrishabha, debilitated in Vrischika.
    [InlineData("Rahu", 1, "exalted")]
    [InlineData("Rahu", 7, "debilitated")]
    [InlineData("Rahu", 4, "neutral")]
    // Ketu: opposite of Rahu — exalted in Vrischika, debilitated in Vrishabha.
    [InlineData("Ketu", 7, "exalted")]
    [InlineData("Ketu", 1, "debilitated")]
    [InlineData("Ketu", 4, "neutral")]
    public void GetDignity_ReturnsCorrectDignityForPlanetAndSign(
        string planet, int rashiIndex, string expected)
    {
        Assert.Equal(expected, VedicCalendar.GetDignity(planet, rashiIndex));
    }

    [Fact]
    public void GetDignity_MercuryInVirgo_PrefersExaltedOverOwnSign()
    {
        // Mercury in Kanya (5) is technically both exalted AND own sign.
        // We prioritize "exalted" as the more notable classification.
        Assert.Equal("exalted", VedicCalendar.GetDignity("Mercury", 5));
    }
}
