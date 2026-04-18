using GeoTimeZone;

namespace ShantiSangha.Jyotish.Services;

/// <summary>
/// Converts a user-entered local birth time into precise UTC using an IANA
/// timezone database (via lat/lon). Handles DST and political timezone
/// changes at the birth moment correctly — much more accurate than the
/// simple longitude/15 mean-solar-time estimate.
/// </summary>
public static class BirthTimeResolver
{
    /// <summary>
    /// Returns the UTC DateTime for a birth moment given local wall-clock
    /// time and birth coordinates. Falls back to longitude-based estimate
    /// when the timezone lookup fails or when no coordinates are available.
    /// </summary>
    public static DateTime ResolveBirthUtc(
        DateOnly localDate, TimeOnly localTime, double? latitude, double? longitude)
    {
        var local = localDate.ToDateTime(localTime, DateTimeKind.Unspecified);

        if (latitude is null || longitude is null)
        {
            // No coordinates — treat as UTC. No better option without place info.
            return DateTime.SpecifyKind(local, DateTimeKind.Utc);
        }

        try
        {
            var ianaId = TimeZoneLookup.GetTimeZone(latitude.Value, longitude.Value).Result;
            var tz = TimeZoneInfo.FindSystemTimeZoneById(ianaId);
            var utc = TimeZoneInfo.ConvertTimeToUtc(local, tz);
            return utc;
        }
        catch
        {
            // Lookup or timezone resolution failed. Fall back to the longitude
            // estimate (15° per hour of mean solar time) — not perfect but at
            // least within ~30 min of the correct offset for most places.
            var approxOffsetHours = longitude.Value / 15.0;
            return DateTime.SpecifyKind(local.AddHours(-approxOffsetHours), DateTimeKind.Utc);
        }
    }
}
