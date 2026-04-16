namespace ShantiSangha.Shared.Jyotish;

/// <summary>
/// Vedic astronomical calculations — sidereal positions using Lahiri ayanamsa.
/// These are approximate calculations suitable for generating AI context.
/// For precise kundli, a dedicated Jyotish library would be needed.
/// </summary>
public static class VedicCalendar
{
    // Lahiri ayanamsa at J2000.0 (Jan 1, 2000) and annual precession rate
    private const double AyanamsaJ2000 = 23.856;
    private const double AyanamsaRate = 0.01397; // degrees per year

    private static readonly string[] Rashis =
    [
        "Mesha", "Vrishabha", "Mithuna", "Karka",
        "Simha", "Kanya", "Tula", "Vrischika",
        "Dhanu", "Makara", "Kumbha", "Meena"
    ];

    private static readonly string[] RashiEnglish =
    [
        "Aries", "Taurus", "Gemini", "Cancer",
        "Leo", "Virgo", "Libra", "Scorpio",
        "Sagittarius", "Capricorn", "Aquarius", "Pisces"
    ];

    private static readonly string[] Nakshatras =
    [
        "Ashwini", "Bharani", "Krittika", "Rohini",
        "Mrigashirsha", "Ardra", "Punarvasu", "Pushya",
        "Ashlesha", "Magha", "Purva Phalguni", "Uttara Phalguni",
        "Hasta", "Chitra", "Swati", "Vishakha",
        "Anuradha", "Jyeshtha", "Mula", "Purva Ashadha",
        "Uttara Ashadha", "Shravana", "Dhanishta", "Shatabhisha",
        "Purva Bhadrapada", "Uttara Bhadrapada", "Revati"
    ];

    private static readonly string[] NakshatraQualities =
    [
        "new beginnings and courage", "transformation and endurance", "fire and purification",
        "growth and creativity", "curiosity and seeking", "storms that clear the way",
        "renewal and return", "nourishment and devotion", "intensity and depth",
        "ancestral power and authority", "rest and enjoyment", "service and discernment",
        "skill and craftsmanship", "brilliance and independence", "flexibility and movement",
        "determination and purpose", "devotion and friendship", "seniority and protection",
        "roots and foundation", "invincibility and courage", "unwavering commitment",
        "listening and learning", "rhythm and abundance", "healing and solitude",
        "fiery transformation", "depth and stability", "completion and transcendence"
    ];

    private static readonly string[] Tithis =
    [
        "Pratipada", "Dwitiya", "Tritiya", "Chaturthi", "Panchami",
        "Shashthi", "Saptami", "Ashtami", "Navami", "Dashami",
        "Ekadashi", "Dwadashi", "Trayodashi", "Chaturdashi", "Purnima/Amavasya"
    ];

    private static readonly string[] TithiQualities =
    [
        "fresh starts", "partnerships", "creativity", "overcoming obstacles", "wisdom",
        "nurturing", "spiritual practice", "transformation", "completion", "dharma",
        "fasting and inner focus", "devotion", "auspicious action", "Shiva's day", "fullness or stillness"
    ];

    private static readonly string[] Yogas =
    [
        "Vishkambha", "Priti", "Ayushman", "Saubhagya", "Shobhana",
        "Atiganda", "Sukarma", "Dhriti", "Shula", "Ganda",
        "Vriddhi", "Dhruva", "Vyaghata", "Harshana", "Vajra",
        "Siddhi", "Vyatipata", "Variyan", "Parigha", "Shiva",
        "Siddha", "Sadhya", "Shubha", "Shukla", "Brahma",
        "Indra", "Vaidhriti"
    ];

    private static readonly string[] Varas =
    [
        "Ravivara", "Somavara", "Mangalavara", "Budhavara",
        "Guruvara", "Shukravara", "Shanivara"
    ];

    private static readonly string[] VaraDeities =
    [
        "Surya (Sun)", "Chandra (Moon)", "Mangala (Mars)", "Budha (Mercury)",
        "Guru (Jupiter)", "Shukra (Venus)", "Shani (Saturn)"
    ];

    /// <summary>
    /// Computes the Lahiri ayanamsa for a given date.
    /// </summary>
    public static double GetAyanamsa(DateTime date)
    {
        var yearsSinceJ2000 = (date - new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc)).TotalDays / 365.25;
        return AyanamsaJ2000 + AyanamsaRate * yearsSinceJ2000;
    }

    /// <summary>
    /// Approximate tropical sun longitude for a given date.
    /// Accurate to ~1 degree — sufficient for rashi determination.
    /// </summary>
    public static double GetTropicalSunLongitude(DateTime date)
    {
        var daysSinceJ2000 = (date - new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc)).TotalDays;
        // Mean longitude of the sun
        var L = (280.46646 + 0.9856474 * daysSinceJ2000) % 360;
        // Mean anomaly
        var M = (357.52911 + 0.9856003 * daysSinceJ2000) % 360;
        var MRad = M * Math.PI / 180;
        // Equation of center (simplified)
        var C = 1.9146 * Math.Sin(MRad) + 0.02 * Math.Sin(2 * MRad);
        var sunLong = (L + C) % 360;
        return sunLong < 0 ? sunLong + 360 : sunLong;
    }

    /// <summary>
    /// Approximate tropical moon longitude for a given date.
    /// Accurate to ~2-3 degrees — sufficient for nakshatra determination.
    /// </summary>
    public static double GetTropicalMoonLongitude(DateTime date)
    {
        var daysSinceJ2000 = (date - new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc)).TotalDays;
        // Simplified lunar longitude
        var L = (218.3165 + 13.17639648 * daysSinceJ2000) % 360;
        var M = (134.9634 + 13.06499295 * daysSinceJ2000) % 360;
        var MRad = M * Math.PI / 180;
        var F = (93.2720 + 13.22935024 * daysSinceJ2000) % 360;
        var FRad = F * Math.PI / 180;
        // Perturbation (simplified)
        var moonLong = L + 6.2894 * Math.Sin(MRad) + 1.274 * Math.Sin(2 * FRad - MRad);
        moonLong %= 360;
        return moonLong < 0 ? moonLong + 360 : moonLong;
    }

    /// <summary>
    /// Convert tropical longitude to sidereal using Lahiri ayanamsa.
    /// </summary>
    public static double ToSidereal(double tropicalLongitude, DateTime date)
    {
        var sidereal = tropicalLongitude - GetAyanamsa(date);
        return sidereal < 0 ? sidereal + 360 : sidereal % 360;
    }

    /// <summary>Get rashi index (0-11) from sidereal longitude.</summary>
    public static int GetRashiIndex(double siderealLongitude) => (int)(siderealLongitude / 30) % 12;

    /// <summary>Get nakshatra index (0-26) from sidereal longitude.</summary>
    public static int GetNakshatraIndex(double siderealLongitude) => (int)(siderealLongitude / (360.0 / 27)) % 27;

    /// <summary>Get rashi name from index.</summary>
    public static string GetRashi(int index) => $"{Rashis[index]} ({RashiEnglish[index]})";

    /// <summary>Get nakshatra name and quality from index.</summary>
    public static (string Name, string Quality) GetNakshatra(int index) => (Nakshatras[index], NakshatraQualities[index]);

    /// <summary>
    /// Compute today's panchang elements.
    /// </summary>
    public static (string Tithi, string TithiQuality, string Vara, string VaraDeity, string Yoga, string Nakshatra, string NakshatraQuality) GetPanchang(DateTime date)
    {
        var sunSidereal = ToSidereal(GetTropicalSunLongitude(date), date);
        var moonSidereal = ToSidereal(GetTropicalMoonLongitude(date), date);

        // Tithi = elongation of moon from sun / 12 degrees
        var elongation = moonSidereal - sunSidereal;
        if (elongation < 0) elongation += 360;
        var tithiIndex = (int)(elongation / 12) % 30;
        var tithiName = Tithis[tithiIndex % 15];
        var paksha = tithiIndex < 15 ? "Shukla" : "Krishna";
        var tithiQuality = TithiQualities[tithiIndex % 15];

        // Vara (weekday)
        var varaIndex = (int)date.DayOfWeek;
        var vara = Varas[varaIndex];
        var varaDeity = VaraDeities[varaIndex];

        // Yoga = (sun + moon sidereal) / (360/27)
        var yogaValue = (sunSidereal + moonSidereal) % 360;
        var yogaIndex = (int)(yogaValue / (360.0 / 27)) % 27;
        var yoga = Yogas[yogaIndex];

        // Moon's nakshatra
        var nakshatraIndex = GetNakshatraIndex(moonSidereal);
        var (nakshatraName, nakshatraQuality) = GetNakshatra(nakshatraIndex);

        return ($"{paksha} {tithiName}", tithiQuality, vara, varaDeity, yoga, nakshatraName, nakshatraQuality);
    }
}
