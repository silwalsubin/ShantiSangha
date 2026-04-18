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
        var sunTrop = VedicCalendar.GetTropicalSunLongitude(birthUtc);
        foreach (var p in planets)
        {
            var sidereal = VedicCalendar.ToSidereal(p.Tropical, birthUtc);
            var rashiIdx = VedicCalendar.GetRashiIndex(sidereal);
            var degInRashi = VedicCalendar.GetDegreeInRashi(sidereal);
            var nakIdx = VedicCalendar.GetNakshatraIndex(sidereal);
            var (nakName, _) = VedicCalendar.GetNakshatra(nakIdx);
            var pada = VedicCalendar.GetPada(sidereal);
            var house = VedicCalendar.GetHouse(sidereal, ascSidereal);

            var dignity = VedicCalendar.GetDignity(p.Name, rashiIdx, degInRashi);
            var navamsaIdx = VedicCalendar.GetNavamsaRashi(sidereal);
            var navamsa = VedicCalendar.GetRashi(navamsaIdx);
            var drekkana = VedicCalendar.GetRashi(VedicCalendar.GetDrekkanaRashi(sidereal));
            var chaturthamsa = VedicCalendar.GetRashi(VedicCalendar.GetChaturthamsaRashi(sidereal));
            var saptamsa = VedicCalendar.GetRashi(VedicCalendar.GetSaptamsaRashi(sidereal));
            var dasamsa = VedicCalendar.GetRashi(VedicCalendar.GetDasamsaRashi(sidereal));
            var dvadasamsa = VedicCalendar.GetRashi(VedicCalendar.GetDvadasamsaRashi(sidereal));
            var shodasamsa = VedicCalendar.GetRashi(VedicCalendar.GetShodasamsaRashi(sidereal));
            var vimsamsa = VedicCalendar.GetRashi(VedicCalendar.GetVimsamsaRashi(sidereal));
            var chaturvimsamsa = VedicCalendar.GetRashi(VedicCalendar.GetChaturvimsamsaRashi(sidereal));
            var vargottama = navamsaIdx == rashiIdx;
            var retro = PlanetaryPositions.IsRetrograde(p.Name, birthUtc);
            var combust = PlanetaryPositions.IsCombust(p.Name, p.Tropical, sunTrop, retro);
            var sandhi = VedicCalendar.IsInSandhi(degInRashi);

            var flags = new List<string>();
            if (dignity != "neutral") flags.Add(dignity.ToUpperInvariant());
            if (vargottama) flags.Add("VARGOTTAMA");
            if (retro) flags.Add("R");
            if (combust) flags.Add("COMBUST");
            if (sandhi) flags.Add("SANDHI");
            var flagLabel = flags.Count > 0 ? $"  [{string.Join(", ", flags)}]" : "";

            // Strip English-in-parens for compactness here
            string Short(string s) => s.Split(' ')[0];

            output.WriteLine(
                $"  {p.Name,-7}  {VedicCalendar.GetRashi(rashiIdx),-23} {degInRashi,5:F2}°  " +
                $"H{house,-2}{flagLabel}");
            output.WriteLine(
                $"           D3 {Short(drekkana),-11} D4 {Short(chaturthamsa),-11} " +
                $"D7 {Short(saptamsa),-11} D9 {Short(navamsa),-11} D10 {Short(dasamsa),-11}");
            output.WriteLine(
                $"           D12 {Short(dvadasamsa),-10} D16 {Short(shodasamsa),-10} " +
                $"D20 {Short(vimsamsa),-10} D24 {Short(chaturvimsamsa),-10}");
            output.WriteLine("");
        }

        output.WriteLine("");
        var dasha = VedicCalendar.GetCurrentDasha(birthUtc, new DateTime(2026, 4, 18, 0, 0, 0, DateTimeKind.Utc));
        output.WriteLine($"DASHA AT 2026-04-18");
        output.WriteLine($"  Mahadasha: {dasha.Mahadasha}  ({dasha.MahadashaStart:yyyy-MM-dd} → {dasha.MahadashaEnd:yyyy-MM-dd})");
        output.WriteLine($"  Antardasha: {dasha.Antardasha}  ({dasha.AntardashaStart:yyyy-MM-dd} → {dasha.AntardashaEnd:yyyy-MM-dd})");
    }
}
