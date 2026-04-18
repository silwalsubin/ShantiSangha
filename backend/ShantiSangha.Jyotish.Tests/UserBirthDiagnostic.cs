using ShantiSangha.Jyotish.Services;
using Xunit;
using Xunit.Abstractions;

namespace ShantiSangha.Jyotish.Tests;

/// <summary>
/// Diagnostic test that prints the full computed chart for a specific birth.
/// Used to manually verify calculations against a reference Jyotish source.
/// </summary>
public class UserBirthDiagnostic(ITestOutputHelper output)
{
    [Fact]
    public void PrintChart_Kathmandu_June22_1990_6AM()
    {
        // Local birth time at Kathmandu
        var birthDate = new DateOnly(1990, 6, 22);
        var birthTime = new TimeOnly(6, 0);
        var lat = 27.7172;
        var lon = 85.3240;

        // Use production code path — IANA timezone resolution from lat/lon
        var birthUtc = BirthTimeResolver.ResolveBirthUtc(birthDate, birthTime, lat, lon);

        output.WriteLine($"Birth local (Kathmandu): {birthDate:yyyy-MM-dd} {birthTime}");
        output.WriteLine($"Birth UTC:               {birthUtc:yyyy-MM-dd HH:mm}");
        output.WriteLine($"Ayanamsa at birth:       {VedicCalendar.GetAyanamsa(birthUtc):F3}°");
        output.WriteLine("");

        // Planetary positions
        var planets = new (string Name, double Tropical)[]
        {
            ("Sun",     VedicCalendar.GetTropicalSunLongitude(birthUtc)),
            ("Moon",    VedicCalendar.GetTropicalMoonLongitude(birthUtc)),
            ("Mercury", PlanetaryPositions.GetTropicalMercuryLongitude(birthUtc)),
            ("Venus",   PlanetaryPositions.GetTropicalVenusLongitude(birthUtc)),
            ("Mars",    PlanetaryPositions.GetTropicalMarsLongitude(birthUtc)),
            ("Jupiter", PlanetaryPositions.GetTropicalJupiterLongitude(birthUtc)),
            ("Saturn",  PlanetaryPositions.GetTropicalSaturnLongitude(birthUtc)),
            ("Rahu",    PlanetaryPositions.GetTropicalRahuLongitude(birthUtc)),
            ("Ketu",    PlanetaryPositions.GetTropicalKetuLongitude(birthUtc))
        };

        // Ascendant
        var ascTropical = VedicCalendar.GetTropicalAscendant(birthUtc, lat, lon);
        var ascSidereal = VedicCalendar.ToSidereal(ascTropical, birthUtc);
        var ascRashiIdx = VedicCalendar.GetRashiIndex(ascSidereal);
        var ascDeg = VedicCalendar.GetDegreeInRashi(ascSidereal);

        output.WriteLine($"LAGNA (Ascendant)");
        output.WriteLine($"  Tropical: {ascTropical:F2}°");
        output.WriteLine($"  Sidereal: {ascSidereal:F2}° → {VedicCalendar.GetRashi(ascRashiIdx)} {ascDeg:F2}°");
        output.WriteLine("");

        output.WriteLine("PLANETS (Sidereal = Tropical − Ayanamsa)");
        output.WriteLine("-------");
        foreach (var p in planets)
        {
            var sidereal = VedicCalendar.ToSidereal(p.Tropical, birthUtc);
            var rashiIdx = VedicCalendar.GetRashiIndex(sidereal);
            var degInRashi = VedicCalendar.GetDegreeInRashi(sidereal);
            var nakIdx = VedicCalendar.GetNakshatraIndex(sidereal);
            var (nakName, _) = VedicCalendar.GetNakshatra(nakIdx);
            var pada = VedicCalendar.GetPada(sidereal);
            var house = VedicCalendar.GetHouse(sidereal, ascSidereal);

            output.WriteLine(
                $"  {p.Name,-7}  Tropical {p.Tropical,7:F2}°  |  Sid {sidereal,7:F2}°  →  " +
                $"{VedicCalendar.GetRashi(rashiIdx)} {degInRashi:F2}°, {nakName} Pada {pada}, House {house}");
        }

        output.WriteLine("");
        var dasha = VedicCalendar.GetCurrentDasha(birthUtc, new DateTime(2026, 4, 18, 0, 0, 0, DateTimeKind.Utc));
        output.WriteLine($"DASHA AT 2026-04-18");
        output.WriteLine($"  Mahadasha: {dasha.Mahadasha}  ({dasha.MahadashaStart:yyyy-MM-dd} → {dasha.MahadashaEnd:yyyy-MM-dd})");
        output.WriteLine($"  Antardasha: {dasha.Antardasha}  ({dasha.AntardashaStart:yyyy-MM-dd} → {dasha.AntardashaEnd:yyyy-MM-dd})");
    }
}
