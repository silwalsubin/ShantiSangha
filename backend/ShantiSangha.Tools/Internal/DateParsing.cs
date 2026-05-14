using System.Globalization;

namespace ShantiSangha.Tools.Internal;

internal static class DateParsing
{
    private static readonly string[] AbsoluteFormats =
    {
        "yyyy-MM-dd",
        "yyyy/MM/dd",
        "MM/dd/yyyy",
        "M/d/yyyy",
        "MMMM d yyyy",
        "MMMM d, yyyy",
        "MMM d yyyy",
        "MMM d, yyyy",
        "d MMMM yyyy",
        "d MMM yyyy",
    };

    private static readonly string[] MonthDayFormats =
    {
        "MMMM d",
        "MMM d",
        "M/d",
        "MM/dd",
        "d MMMM",
        "d MMM",
    };

    public static DateOnly? Parse(string input, DateOnly today)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;

        var trimmed = input.Trim();

        if (TryRelative(trimmed, today, out var relative))
            return relative;

        if (DateOnly.TryParseExact(trimmed, AbsoluteFormats, CultureInfo.InvariantCulture,
                DateTimeStyles.None, out var exact))
            return exact;

        foreach (var fmt in MonthDayFormats)
        {
            if (DateTime.TryParseExact(trimmed, fmt, CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out var partial))
            {
                var candidate = new DateOnly(today.Year, partial.Month, partial.Day);
                return candidate >= today ? candidate : candidate.AddYears(1);
            }
        }

        if (DateOnly.TryParse(trimmed, CultureInfo.InvariantCulture, DateTimeStyles.None, out var loose))
            return loose;

        return null;
    }

    private static bool TryRelative(string input, DateOnly today, out DateOnly result)
    {
        var lower = input.ToLowerInvariant();

        switch (lower)
        {
            case "today":
                result = today; return true;
            case "tomorrow":
                result = today.AddDays(1); return true;
            case "yesterday":
                result = today.AddDays(-1); return true;
        }

        if (lower.StartsWith("in ") && lower.EndsWith(" days"))
        {
            var middle = lower["in ".Length..^" days".Length];
            if (int.TryParse(middle, out var days))
            {
                result = today.AddDays(days);
                return true;
            }
        }

        if (lower.StartsWith("next "))
        {
            if (TryParseDayOfWeek(lower["next ".Length..], out var dow))
            {
                var diff = ((int)dow - (int)today.DayOfWeek + 7) % 7;
                if (diff == 0) diff = 7;
                result = today.AddDays(diff);
                return true;
            }
        }

        if (lower.StartsWith("this "))
        {
            if (TryParseDayOfWeek(lower["this ".Length..], out var dow))
            {
                var diff = ((int)dow - (int)today.DayOfWeek + 7) % 7;
                result = today.AddDays(diff);
                return true;
            }
        }

        if (TryParseDayOfWeek(lower, out var bareDow))
        {
            var diff = ((int)bareDow - (int)today.DayOfWeek + 7) % 7;
            if (diff == 0) diff = 7;
            result = today.AddDays(diff);
            return true;
        }

        result = default;
        return false;
    }

    private static bool TryParseDayOfWeek(string input, out DayOfWeek dow)
    {
        switch (input.Trim())
        {
            case "monday": case "mon": dow = DayOfWeek.Monday; return true;
            case "tuesday": case "tue": case "tues": dow = DayOfWeek.Tuesday; return true;
            case "wednesday": case "wed": dow = DayOfWeek.Wednesday; return true;
            case "thursday": case "thu": case "thurs": dow = DayOfWeek.Thursday; return true;
            case "friday": case "fri": dow = DayOfWeek.Friday; return true;
            case "saturday": case "sat": dow = DayOfWeek.Saturday; return true;
            case "sunday": case "sun": dow = DayOfWeek.Sunday; return true;
        }
        dow = default;
        return false;
    }
}
