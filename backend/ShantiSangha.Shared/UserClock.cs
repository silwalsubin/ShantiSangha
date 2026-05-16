namespace ShantiSangha.Shared;

public static class UserClock
{
    public static DateOnly TodayFor(string? ianaTimezoneId)
    {
        var tz = ResolveTimezone(ianaTimezoneId);
        var local = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, tz);
        return DateOnly.FromDateTime(local);
    }

    private static TimeZoneInfo ResolveTimezone(string? ianaTimezoneId)
    {
        if (string.IsNullOrWhiteSpace(ianaTimezoneId))
            return TimeZoneInfo.Utc;
        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById(ianaTimezoneId);
        }
        catch
        {
            return TimeZoneInfo.Utc;
        }
    }
}
