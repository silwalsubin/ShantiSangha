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
}
