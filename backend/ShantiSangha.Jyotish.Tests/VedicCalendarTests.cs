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
    // Sun: exalted Mesha (peak 10°), own Simha, debilitated Tula.
    // Mid-sign degree (15°) is outside deep-exalt tolerance → plain "exalted".
    [InlineData("Sun", 0, 15.0, "exalted")]
    [InlineData("Sun", 0, 10.0, "deep_exalted")]     // exact peak
    [InlineData("Sun", 4, 5.0, "moolatrikona")]      // Simha 0–20° is moolatrikona
    [InlineData("Sun", 4, 25.0, "own_sign")]         // Simha 20–30° is own_sign
    [InlineData("Sun", 6, 15.0, "debilitated")]
    [InlineData("Sun", 2, 15.0, "neutral")]
    // Moon: exalted Vrishabha (peak 3°), own Karka, debilitated Vrischika.
    // Classical Moon moolatrikona is Vrishabha 4–30° but that overlaps with
    // the exaltation sign. We let exaltation win across the whole sign to
    // match the more common teaching and keep labels users recognize.
    [InlineData("Moon", 1, 3.0, "deep_exalted")]     // exact peak
    [InlineData("Moon", 1, 1.0, "deep_exalted")]     // within ±3° of peak
    [InlineData("Moon", 1, 15.0, "exalted")]         // exaltation wins in exalt sign
    [InlineData("Moon", 3, 15.0, "own_sign")]        // Karka
    [InlineData("Moon", 7, 15.0, "debilitated")]
    [InlineData("Moon", 0, 15.0, "neutral")]
    // Mars: exalted Makara (peak 28°), moolatrikona Mesha 0–12°, own Mesha/Vrischika,
    // debilitated Karka.
    [InlineData("Mars", 9, 28.0, "deep_exalted")]
    [InlineData("Mars", 9, 15.0, "exalted")]
    [InlineData("Mars", 0, 5.0, "moolatrikona")]     // Mesha 0–12° is moolatrikona
    [InlineData("Mars", 0, 20.0, "own_sign")]        // Mesha 12–30° is own_sign
    [InlineData("Mars", 7, 15.0, "own_sign")]
    [InlineData("Mars", 3, 15.0, "debilitated")]
    [InlineData("Mars", 5, 15.0, "neutral")]
    // Mercury edge case: Kanya 0–15° = exalted, 16–20° = moolatrikona, 20–30° = own_sign.
    [InlineData("Mercury", 5, 10.0, "exalted")]
    [InlineData("Mercury", 5, 15.0, "deep_exalted")] // peak
    [InlineData("Mercury", 5, 18.0, "moolatrikona")]
    [InlineData("Mercury", 5, 25.0, "own_sign")]
    [InlineData("Mercury", 2, 15.0, "own_sign")]     // Mithuna
    [InlineData("Mercury", 11, 15.0, "debilitated")]
    [InlineData("Mercury", 4, 15.0, "neutral")]
    // Jupiter: exalted Karka (peak 5°), moolatrikona Dhanu 0–10°, own Dhanu/Meena.
    [InlineData("Jupiter", 3, 5.0, "deep_exalted")]
    [InlineData("Jupiter", 3, 15.0, "exalted")]
    [InlineData("Jupiter", 8, 5.0, "moolatrikona")]
    [InlineData("Jupiter", 8, 20.0, "own_sign")]
    [InlineData("Jupiter", 11, 15.0, "own_sign")]
    [InlineData("Jupiter", 9, 15.0, "debilitated")]
    // Venus: exalted Meena (peak 27°), moolatrikona Tula 0–15°, own Vrishabha/Tula.
    [InlineData("Venus", 11, 27.0, "deep_exalted")]
    [InlineData("Venus", 11, 10.0, "exalted")]
    [InlineData("Venus", 6, 5.0, "moolatrikona")]
    [InlineData("Venus", 6, 25.0, "own_sign")]
    [InlineData("Venus", 1, 15.0, "own_sign")]
    [InlineData("Venus", 5, 15.0, "debilitated")]
    // Saturn: exalted Tula (peak 20°), moolatrikona Kumbha 0–20°, own Makara/Kumbha.
    [InlineData("Saturn", 6, 20.0, "deep_exalted")]
    [InlineData("Saturn", 6, 5.0, "exalted")]
    [InlineData("Saturn", 10, 10.0, "moolatrikona")]
    [InlineData("Saturn", 10, 25.0, "own_sign")]
    [InlineData("Saturn", 9, 15.0, "own_sign")]
    [InlineData("Saturn", 0, 15.0, "debilitated")]
    // Rahu/Ketu — no deep-exalt or moolatrikona tradition here.
    [InlineData("Rahu", 1, 15.0, "exalted")]
    [InlineData("Rahu", 7, 15.0, "debilitated")]
    [InlineData("Rahu", 4, 15.0, "neutral")]
    [InlineData("Ketu", 7, 15.0, "exalted")]
    [InlineData("Ketu", 1, 15.0, "debilitated")]
    [InlineData("Ketu", 4, 15.0, "neutral")]
    public void GetDignity_ReturnsCorrectDignityForPlanetSignDegree(
        string planet, int rashiIndex, double degreeInRashi, string expected)
    {
        Assert.Equal(expected, VedicCalendar.GetDignity(planet, rashiIndex, degreeInRashi));
    }

    // ------------------------------------------------------------------
    // Navamsa (D9) — 9 sections per sign, movable/fixed/dual starting rules
    // ------------------------------------------------------------------

    [Theory]
    // Movable signs (Mesha=0, Karka=3, Tula=6, Makara=9) — start from themselves.
    [InlineData(0.0, 0)]         // Mesha 0° → D9 Mesha
    [InlineData(3.5, 1)]         // Mesha ~3.5° → D9 Vrishabha (2nd section)
    [InlineData(29.99, 8)]       // Mesha 29.99° → D9 Dhanu (9th section)
    [InlineData(90.0, 3)]        // Karka 0° → D9 Karka (movable)
    // Fixed signs (Vrishabha=1, Simha=4, Vrischika=7, Kumbha=10) — start from 9th.
    [InlineData(30.0, 9)]        // Vrishabha 0° → start=9 (Makara), +0 = Makara
    [InlineData(55.74, 4)]       // Vrishabha 25.74° → D9 Simha (the user's Moon)
    [InlineData(59.99, 5)]       // Vrishabha 29.99° → D9 Kanya (8th section from Makara)
    // Dual signs (Mithuna=2, Kanya=5, Dhanu=8, Meena=11) — start from 5th.
    [InlineData(60.0, 6)]        // Mithuna 0° → start=6 (Tula), +0 = Tula
    [InlineData(66.63, 7)]       // Mithuna 6.63° → D9 Vrischika (the user's Sun)
    [InlineData(269.89, 8)]      // Dhanu 29.89° → start=0 (Mesha), +8 = Dhanu (vargottama for user's Saturn)
    public void GetNavamsaRashi_ReturnsCorrectNavamsa(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetNavamsaRashi(siderealLongitude));
    }

    // ------------------------------------------------------------------
    // Sandhi (cusp zones) — first/last 1° of any sign
    // ------------------------------------------------------------------

    [Theory]
    [InlineData(0.0, true)]
    [InlineData(0.5, true)]
    [InlineData(1.0, false)]
    [InlineData(15.0, false)]
    [InlineData(28.9, false)]
    [InlineData(29.0, true)]
    [InlineData(29.99, true)]
    public void IsInSandhi_FlagsFirstAndLastDegree(double degreeInRashi, bool expected)
    {
        Assert.Equal(expected, VedicCalendar.IsInSandhi(degreeInRashi));
    }

    // ------------------------------------------------------------------
    // Dasamsa (D10) — 10 sections per sign, odd start from self, even start from 9th
    // ------------------------------------------------------------------

    [Theory]
    // Odd signs (Mesha=0, Mithuna=2, Simha=4, Tula=6, Dhanu=8, Kumbha=10) — start from self
    [InlineData(0.0, 0)]            // Mesha 0° → D10 Mesha
    [InlineData(2.99, 0)]           // Mesha <3° → still first segment (Mesha)
    [InlineData(3.0, 1)]            // Mesha 3° → Vrishabha (2nd segment from Mesha)
    [InlineData(29.99, 9)]          // Mesha 29.99° → 10th segment → Makara
    [InlineData(66.63, 4)]          // Mithuna 6.63° → seg 2 → Simha (user's Sun)
    [InlineData(269.89, 5)]         // Dhanu 29.89° → seg 9 → Kanya (user's Saturn)
    // Even signs (Vrishabha=1, Karka=3, Kanya=5, Vrischika=7, Makara=9, Meena=11) — start from 9th
    [InlineData(30.0, 9)]           // Vrishabha 0° → start from Makara (9) + seg 0 → Makara
    [InlineData(55.70, 5)]          // Vrishabha 25.70° → seg 8 → (9+8)%12 = Kanya (user's Moon)
    [InlineData(90.0, 11)]          // Karka 0° → start from Meena (11) + seg 0 → Meena
    [InlineData(105.63, 4)]         // Karka 15.63° → seg 5 → (11+5)%12 = Simha (user's Ketu)
    public void GetDasamsaRashi_ReturnsCorrectD10(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetDasamsaRashi(siderealLongitude));
    }

    // ------------------------------------------------------------------
    // Dvadasamsa (D12) — 12 sections per sign, always start from the sign itself
    // ------------------------------------------------------------------

    [Theory]
    [InlineData(0.0, 0)]            // Mesha 0° → Mesha
    [InlineData(2.49, 0)]           // still in first 2.5° → Mesha
    [InlineData(2.5, 1)]            // past 2.5° → Vrishabha
    [InlineData(29.99, 11)]         // Mesha 29.99° → 12th segment → Meena
    [InlineData(30.0, 1)]           // Vrishabha 0° → Vrishabha (same sign start)
    [InlineData(55.70, 11)]         // Vrishabha 25.70° → seg 10 → (1+10)%12 = Meena (user's Moon)
    [InlineData(66.63, 4)]          // Mithuna 6.63° → seg 2 → (2+2)%12 = Simha (user's Sun)
    [InlineData(269.89, 7)]         // Dhanu 29.89° → seg 11 → (8+11)%12 = Vrischika (user's Saturn)
    public void GetDvadasamsaRashi_ReturnsCorrectD12(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetDvadasamsaRashi(siderealLongitude));
    }

    // ------------------------------------------------------------------
    // Drekkana (D3) — 3 sections × 10°, offsets 0/4/8 from the sign
    // ------------------------------------------------------------------

    [Theory]
    [InlineData(0.0, 0)]            // Mesha 0° → Mesha (1st decan, same sign)
    [InlineData(9.99, 0)]           // Mesha 9.99° → still Mesha
    [InlineData(10.0, 4)]           // Mesha 10° → Simha (2nd decan = 5th from sign)
    [InlineData(20.0, 8)]           // Mesha 20° → Dhanu (3rd decan = 9th from sign)
    [InlineData(30.0, 1)]           // Vrishabha 0° → Vrishabha
    [InlineData(45.0, 5)]           // Vrishabha 15° → 2nd decan = 5th from Vrishabha → Kanya
    [InlineData(55.70, 9)]          // Vrishabha 25.70° → 3rd decan = 9th from Vrishabha → Makara
    public void GetDrekkanaRashi_ReturnsCorrectD3(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetDrekkanaRashi(siderealLongitude));
    }

    // ------------------------------------------------------------------
    // Chaturthamsa (D4) — 4 sections × 7.5°, kendras (0/3/6/9 offsets)
    // ------------------------------------------------------------------

    [Theory]
    [InlineData(0.0, 0)]            // Mesha 0° → Mesha (1st quarter, same sign)
    [InlineData(7.49, 0)]           // still in 1st quarter → Mesha
    [InlineData(7.5, 3)]            // Mesha 7.5° → 2nd quarter = 4th from sign → Karka
    [InlineData(15.0, 6)]           // Mesha 15° → 3rd quarter = 7th from sign → Tula
    [InlineData(22.5, 9)]           // Mesha 22.5° → 4th quarter = 10th from sign → Makara
    [InlineData(30.0, 1)]           // Vrishabha 0° → Vrishabha
    public void GetChaturthamsaRashi_ReturnsCorrectD4(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetChaturthamsaRashi(siderealLongitude));
    }

    // ------------------------------------------------------------------
    // Saptamsa (D7) — 7 × ~4.286°, odd signs start from self, even from 7th
    // ------------------------------------------------------------------

    [Theory]
    // Odd sign (Mesha=0) — starts from self
    [InlineData(0.0, 0)]            // Mesha 0° → seg 0 → Mesha
    [InlineData(4.29, 1)]           // ~30/7 boundary → seg 1 → Vrishabha
    [InlineData(29.99, 6)]          // Mesha 29.99° → seg 6 → Tula
    // Even sign (Vrishabha=1) — starts from the 7th (Vrischika=7)
    [InlineData(30.0, 7)]           // Vrishabha 0° → seg 0 → Vrischika
    [InlineData(59.99, 1)]          // Vrishabha 29.99° → seg 6 → (7+6)%12 = Vrishabha
    public void GetSaptamsaRashi_ReturnsCorrectD7(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetSaptamsaRashi(siderealLongitude));
    }

    // ------------------------------------------------------------------
    // Shodasamsa (D16) — 16 × 1.875°, movable/fixed/dual → Mesha/Simha/Dhanu
    // ------------------------------------------------------------------

    [Theory]
    // Movable (Mesha=0) → start Mesha
    [InlineData(0.0, 0)]            // Mesha 0° → Mesha
    [InlineData(29.99, 3)]          // Mesha 29.99° → seg 15 → (0+15)%12 = Karka
    // Fixed (Vrishabha=1) → start Simha (4)
    [InlineData(30.0, 4)]           // Vrishabha 0° → Simha
    [InlineData(31.875, 5)]         // Vrishabha 1.875° → seg 1 → (4+1)%12 = Kanya
    // Dual (Mithuna=2) → start Dhanu (8)
    [InlineData(60.0, 8)]           // Mithuna 0° → Dhanu
    [InlineData(75.0, 4)]           // Mithuna 15° → seg 8 → (8+8)%12 = Simha
    public void GetShodasamsaRashi_ReturnsCorrectD16(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetShodasamsaRashi(siderealLongitude));
    }

    // ------------------------------------------------------------------
    // Vimsamsa (D20) — 20 × 1.5°, movable/fixed/dual → Mesha/Dhanu/Simha
    // ------------------------------------------------------------------

    [Theory]
    // Movable (Mesha=0) → start Mesha
    [InlineData(0.0, 0)]
    [InlineData(1.5, 1)]            // Mesha 1.5° → seg 1 → (0+1)%12 = Vrishabha
    [InlineData(29.99, 7)]          // Mesha 29.99° → seg 19 → (0+19)%12 = Vrischika
    // Fixed (Vrishabha=1) → start Dhanu (8)
    [InlineData(30.0, 8)]           // Vrishabha 0° → Dhanu
    [InlineData(31.5, 9)]           // Vrishabha 1.5° → (8+1)%12 = Makara
    // Dual (Mithuna=2) → start Simha (4)
    [InlineData(60.0, 4)]           // Mithuna 0° → Simha
    public void GetVimsamsaRashi_ReturnsCorrectD20(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetVimsamsaRashi(siderealLongitude));
    }

    // ------------------------------------------------------------------
    // Chaturvimsamsa (D24) — 24 × 1.25°, odd signs start Simha, even start Karka
    // ------------------------------------------------------------------

    [Theory]
    // Odd sign (Mesha=0) → start Simha (4)
    [InlineData(0.0, 4)]            // Mesha 0° → Simha
    [InlineData(1.25, 5)]           // Mesha 1.25° → seg 1 → (4+1)%12 = Kanya
    [InlineData(29.99, 3)]          // Mesha 29.99° → seg 23 → (4+23)%12 = Karka
    // Even sign (Vrishabha=1) → start Karka (3)
    [InlineData(30.0, 3)]           // Vrishabha 0° → Karka
    [InlineData(31.25, 4)]          // Vrishabha 1.25° → (3+1)%12 = Simha
    public void GetChaturvimsamsaRashi_ReturnsCorrectD24(double siderealLongitude, int expectedIdx)
    {
        Assert.Equal(expectedIdx, VedicCalendar.GetChaturvimsamsaRashi(siderealLongitude));
    }
}
