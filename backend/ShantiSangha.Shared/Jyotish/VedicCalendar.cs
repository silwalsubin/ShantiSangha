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
    /// Uses major perturbation terms for ~1 degree accuracy.
    /// </summary>
    public static double GetTropicalMoonLongitude(DateTime date)
    {
        var daysSinceJ2000 = (date - new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc)).TotalDays;
        var T = daysSinceJ2000 / 36525.0; // Julian centuries

        // Mean elements
        var Lp = Normalize(218.3165 + 481267.8813 * T); // Mean longitude
        var D = Normalize(297.8502 + 445267.1115 * T);  // Mean elongation
        var M = Normalize(357.5291 + 35999.0503 * T);   // Sun's mean anomaly
        var Mp = Normalize(134.9634 + 477198.8676 * T);  // Moon's mean anomaly
        var F = Normalize(93.2720 + 483202.0175 * T);   // Argument of latitude

        var DRad = D * Math.PI / 180;
        var MRad = M * Math.PI / 180;
        var MpRad = Mp * Math.PI / 180;
        var FRad = F * Math.PI / 180;

        // Major perturbation terms (Meeus, Astronomical Algorithms)
        var moonLong = Lp
            + 6.2894 * Math.Sin(MpRad)
            + 1.2743 * Math.Sin(2 * DRad - MpRad)
            + 0.6583 * Math.Sin(2 * DRad)
            + 0.2136 * Math.Sin(2 * MpRad)
            - 0.1856 * Math.Sin(MRad)
            - 0.1143 * Math.Sin(2 * FRad)
            + 0.0588 * Math.Sin(2 * DRad - 2 * MpRad)
            + 0.0572 * Math.Sin(2 * DRad - MRad - MpRad)
            + 0.0533 * Math.Sin(2 * DRad + MpRad)
            - 0.0459 * Math.Sin(2 * DRad - MRad)
            + 0.0410 * Math.Sin(MRad - MpRad);

        return Normalize(moonLong);
    }

    private static double Normalize(double degrees)
    {
        var result = degrees % 360;
        return result < 0 ? result + 360 : result;
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
