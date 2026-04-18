using ShantiSangha.Jyotish.Services;
using Xunit;
using Xunit.Abstractions;

namespace ShantiSangha.Jyotish.Tests;

/// <summary>
/// Regression tests comparing our simplified orbital formulas against NASA JPL
/// Horizons ephemeris (gold-standard reference). JPL values captured via the
/// HORIZONS REST API at https://ssd.jpl.nasa.gov/api/horizons.api
///
/// Geocentric apparent ecliptic longitude, referred to Earth mean equator and
/// equinox of reference epoch (J2000), matches what our tropical routines return.
/// Tolerance: ≤2° — the inherent accuracy of Schlyter's simplified formulas.
/// </summary>
public class JplReferenceAccuracy(ITestOutputHelper output)
{
    private static double Diff(double mine, double reference)
    {
        var d = Math.Abs(mine - reference) % 360;
        return d > 180 ? 360 - d : d;
    }

    // Reference: 1990-06-22 00:15 UTC (user's birth time in Kathmandu, 6:00 NPT)
    [Theory]
    [InlineData("Sun",      90.3461994, 2.0)]
    [InlineData("Moon",     79.4466597, 2.0)]
    [InlineData("Mercury",  77.7945475, 2.0)]
    [InlineData("Venus",    56.4525291, 2.0)]
    [InlineData("Mars",     15.6962859, 2.0)]
    [InlineData("Jupiter", 107.3111045, 2.0)]
    [InlineData("Saturn",  293.6301370, 2.0)]
    public void MatchesJpl_At1990_06_22_00_15_UTC(string planet, double jpl, double tolerance)
    {
        var date = new DateTime(1990, 6, 22, 0, 15, 0, DateTimeKind.Utc);
        var mine = planet switch
        {
            "Sun" => VedicCalendar.GetTropicalSunLongitude(date),
            "Moon" => VedicCalendar.GetTropicalMoonLongitude(date),
            "Mercury" => PlanetaryPositions.GetTropicalMercuryLongitude(date),
            "Venus" => PlanetaryPositions.GetTropicalVenusLongitude(date),
            "Mars" => PlanetaryPositions.GetTropicalMarsLongitude(date),
            "Jupiter" => PlanetaryPositions.GetTropicalJupiterLongitude(date),
            "Saturn" => PlanetaryPositions.GetTropicalSaturnLongitude(date),
            _ => throw new ArgumentException(planet)
        };

        var err = Diff(mine, jpl);
        output.WriteLine($"{planet,-8}  mine={mine,8:F4}°  jpl={jpl,8:F4}°  err={err:F3}°");
        Assert.True(err <= tolerance, $"{planet} error {err:F3}° exceeds tolerance {tolerance}°");
    }

    // Reference: 2024-06-15 12:00 UTC
    [Theory]
    [InlineData("Sun",      84.8758982, 2.0)]
    [InlineData("Mercury",  85.8842471, 2.0)]
    [InlineData("Venus",    87.8327314, 2.0)]
    [InlineData("Mars",     34.6690861, 2.0)]
    [InlineData("Jupiter",  64.7670259, 2.0)]
    [InlineData("Saturn",  349.2581857, 2.0)]
    public void MatchesJpl_At2024_06_15_12_00_UTC(string planet, double jpl, double tolerance)
    {
        var date = new DateTime(2024, 6, 15, 12, 0, 0, DateTimeKind.Utc);
        var mine = planet switch
        {
            "Sun" => VedicCalendar.GetTropicalSunLongitude(date),
            "Mercury" => PlanetaryPositions.GetTropicalMercuryLongitude(date),
            "Venus" => PlanetaryPositions.GetTropicalVenusLongitude(date),
            "Mars" => PlanetaryPositions.GetTropicalMarsLongitude(date),
            "Jupiter" => PlanetaryPositions.GetTropicalJupiterLongitude(date),
            "Saturn" => PlanetaryPositions.GetTropicalSaturnLongitude(date),
            _ => throw new ArgumentException(planet)
        };

        var err = Diff(mine, jpl);
        output.WriteLine($"{planet,-8}  mine={mine,8:F4}°  jpl={jpl,8:F4}°  err={err:F3}°");
        Assert.True(err <= tolerance, $"{planet} error {err:F3}° exceeds tolerance {tolerance}°");
    }
}
