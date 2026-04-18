using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Jyotish.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Jyotish.Controllers;

[ApiController]
[Authorize]
[Route("api/jyotish")]
public class JyotishController(
    ICurrentUser currentUser,
    IProfileQueryService profileQuery) : ControllerBase
{
    /// <summary>
    /// Returns the user's Vedic identity — rashi (moon sign), nakshatra.
    /// Only available if the user has provided birth details.
    /// </summary>
    [HttpGet("identity")]
    public async Task<IActionResult> GetIdentity(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var birth = await profileQuery.GetBirthInfoAsync(user.Id, ct);
        if (birth.BirthDate is null)
            return Ok(new { Available = false });

        var birthDate = birth.BirthDate.Value;
        var birthHour = 12.0;
        if (birth.BirthTime is not null && TimeOnly.TryParse(birth.BirthTime, out var parsedTime))
            birthHour = parsedTime.Hour + parsedTime.Minute / 60.0;

        var birthDateTime = birthDate.ToDateTime(
            TimeOnly.FromTimeSpan(TimeSpan.FromHours(birthHour)), DateTimeKind.Utc);

        // Sun rashi
        var sunSidereal = VedicCalendar.ToSidereal(
            VedicCalendar.GetTropicalSunLongitude(birthDateTime), birthDateTime);
        var sunRashi = VedicCalendar.GetRashi(VedicCalendar.GetRashiIndex(sunSidereal));

        // Moon rashi + nakshatra (only with birth time)
        string? moonRashi = null;
        string? nakshatra = null;
        string? nakshatraQuality = null;

        if (birth.BirthTime is not null)
        {
            var moonSidereal = VedicCalendar.ToSidereal(
                VedicCalendar.GetTropicalMoonLongitude(birthDateTime), birthDateTime);
            moonRashi = VedicCalendar.GetRashi(VedicCalendar.GetRashiIndex(moonSidereal));

            var nakshatraIndex = VedicCalendar.GetNakshatraIndex(moonSidereal);
            var (name, quality) = VedicCalendar.GetNakshatra(nakshatraIndex);
            nakshatra = name;
            nakshatraQuality = quality;
        }

        return Ok(new
        {
            Available = true,
            SunRashi = sunRashi,
            MoonRashi = moonRashi,
            Nakshatra = nakshatra,
            NakshatraQuality = nakshatraQuality
        });
    }

    /// <summary>
    /// Returns a detailed Vedic birth chart: nakshatra attributes, all 9 planets with
    /// sidereal positions and house placements, and Ascendant. Requires birth date,
    /// time, and place (lat/lon stored as "lat,lon" in BirthPlace).
    /// </summary>
    [HttpGet("chart")]
    public async Task<IActionResult> GetChart(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var birth = await profileQuery.GetBirthInfoAsync(user.Id, ct);
        if (birth.BirthDate is null || birth.BirthTime is null)
            return Ok(new { Available = false, Reason = "missing_birth_date_or_time" });

        if (!TimeOnly.TryParse(birth.BirthTime, out var parsedTime))
            return Ok(new { Available = false, Reason = "invalid_birth_time" });

        var birthDate = birth.BirthDate.Value;
        var birthDateTime = birthDate.ToDateTime(parsedTime, DateTimeKind.Utc);

        // BirthPlace is stored as "lat,lon" — try to parse for ascendant + houses
        double? latitude = null, longitude = null;
        if (!string.IsNullOrWhiteSpace(birth.BirthPlace))
        {
            var parts = birth.BirthPlace.Split(',');
            if (parts.Length == 2
                && double.TryParse(parts[0].Trim(), System.Globalization.CultureInfo.InvariantCulture, out var lat)
                && double.TryParse(parts[1].Trim(), System.Globalization.CultureInfo.InvariantCulture, out var lon))
            {
                latitude = lat;
                longitude = lon;
            }
        }

        // Nakshatra attributes (from moon's sidereal position at birth)
        var moonTropical = VedicCalendar.GetTropicalMoonLongitude(birthDateTime);
        var moonSidereal = VedicCalendar.ToSidereal(moonTropical, birthDateTime);
        var moonNakshatraIdx = VedicCalendar.GetNakshatraIndex(moonSidereal);
        var (moonNakshatraName, moonNakshatraQuality) = VedicCalendar.GetNakshatra(moonNakshatraIdx);
        var moonPada = VedicCalendar.GetPada(moonSidereal);

        var nakshatraAttrs = new
        {
            Name = moonNakshatraName,
            Quality = moonNakshatraQuality,
            Pada = moonPada,
            Yoni = VedicCalendar.GetNakshatraYoni(moonNakshatraIdx),
            Nadi = VedicCalendar.GetNakshatraNadi(moonNakshatraIdx),
            Gana = VedicCalendar.GetNakshatraGana(moonNakshatraIdx),
            Deity = VedicCalendar.GetNakshatraDeity(moonNakshatraIdx),
            Lord = VedicCalendar.GetNakshatraLord(moonNakshatraIdx)
        };

        // Compute tropical longitudes for all 9 planets
        var planetLongitudes = new (string Name, double Tropical)[]
        {
            ("Sun", VedicCalendar.GetTropicalSunLongitude(birthDateTime)),
            ("Moon", moonTropical),
            ("Mercury", PlanetaryPositions.GetTropicalMercuryLongitude(birthDateTime)),
            ("Venus", PlanetaryPositions.GetTropicalVenusLongitude(birthDateTime)),
            ("Mars", PlanetaryPositions.GetTropicalMarsLongitude(birthDateTime)),
            ("Jupiter", PlanetaryPositions.GetTropicalJupiterLongitude(birthDateTime)),
            ("Saturn", PlanetaryPositions.GetTropicalSaturnLongitude(birthDateTime)),
            ("Rahu", PlanetaryPositions.GetTropicalRahuLongitude(birthDateTime)),
            ("Ketu", PlanetaryPositions.GetTropicalKetuLongitude(birthDateTime))
        };

        // Ascendant (Lagna) — requires lat/lon
        double? ascendantSidereal = null;
        object? lagna = null;
        if (latitude.HasValue && longitude.HasValue)
        {
            var ascTropical = VedicCalendar.GetTropicalAscendant(birthDateTime, latitude.Value, longitude.Value);
            ascendantSidereal = VedicCalendar.ToSidereal(ascTropical, birthDateTime);
            var ascRashiIdx = VedicCalendar.GetRashiIndex(ascendantSidereal.Value);
            var ascNakIdx = VedicCalendar.GetNakshatraIndex(ascendantSidereal.Value);
            var (ascNakName, ascNakQuality) = VedicCalendar.GetNakshatra(ascNakIdx);
            lagna = new
            {
                Rashi = VedicCalendar.GetRashi(ascRashiIdx),
                Degree = Math.Round(VedicCalendar.GetDegreeInRashi(ascendantSidereal.Value), 2),
                Nakshatra = ascNakName,
                NakshatraQuality = ascNakQuality,
                Pada = VedicCalendar.GetPada(ascendantSidereal.Value)
            };
        }

        // Build planet rows
        var planets = planetLongitudes.Select(p =>
        {
            var sidereal = VedicCalendar.ToSidereal(p.Tropical, birthDateTime);
            var rashiIdx = VedicCalendar.GetRashiIndex(sidereal);
            var nakIdx = VedicCalendar.GetNakshatraIndex(sidereal);
            var (nakName, nakQuality) = VedicCalendar.GetNakshatra(nakIdx);
            int? house = ascendantSidereal.HasValue
                ? VedicCalendar.GetHouse(sidereal, ascendantSidereal.Value)
                : (int?)null;

            return new
            {
                Name = p.Name,
                Rashi = VedicCalendar.GetRashi(rashiIdx),
                Degree = Math.Round(VedicCalendar.GetDegreeInRashi(sidereal), 2),
                Nakshatra = nakName,
                NakshatraQuality = nakQuality,
                Pada = VedicCalendar.GetPada(sidereal),
                House = house,
                Nature = VedicCalendar.ClassifyPlanet(p.Name)
            };
        }).ToList();

        // Current dasha
        var dasha = VedicCalendar.GetCurrentDasha(birthDateTime, DateTime.UtcNow);

        return Ok(new
        {
            Available = true,
            Birth = new
            {
                Date = birthDate.ToString("yyyy-MM-dd"),
                Time = birth.BirthTime,
                Place = birth.BirthPlace,
                HasCoordinates = latitude.HasValue && longitude.HasValue
            },
            Nakshatra = nakshatraAttrs,
            Lagna = lagna,
            Planets = planets,
            Dasha = new
            {
                Mahadasha = dasha.Mahadasha,
                Antardasha = dasha.Antardasha,
                AntardashaStart = dasha.AntardashaStart.ToString("yyyy-MM-dd"),
                AntardashaEnd = dasha.AntardashaEnd.ToString("yyyy-MM-dd"),
                MahadashaStart = dasha.MahadashaStart.ToString("yyyy-MM-dd"),
                MahadashaEnd = dasha.MahadashaEnd.ToString("yyyy-MM-dd")
            }
        });
    }
}
