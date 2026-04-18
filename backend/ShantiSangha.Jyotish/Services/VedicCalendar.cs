namespace ShantiSangha.Jyotish.Services;

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

    /// <summary>Yoni (animal energy) for each of the 27 nakshatras — traditional Jyotish attribute.</summary>
    private static readonly string[] NakshatraYonis =
    [
        "Horse (Ashwa)", "Elephant (Gaja)", "Sheep (Mesha)", "Serpent (Sarpa)",
        "Serpent (Sarpa)", "Dog (Shvana)", "Cat (Marjara)", "Sheep (Mesha)",
        "Cat (Marjara)", "Rat (Akhu)", "Rat (Akhu)", "Cow (Gau)",
        "Buffalo (Mahisha)", "Tiger (Vyaghra)", "Buffalo (Mahisha)", "Tiger (Vyaghra)",
        "Deer (Mriga)", "Deer (Mriga)", "Dog (Shvana)", "Monkey (Vanara)",
        "Mongoose (Nakula)", "Monkey (Vanara)", "Lion (Simha)", "Horse (Ashwa)",
        "Lion (Simha)", "Cow (Gau)", "Elephant (Gaja)"
    ];

    /// <summary>Nadi — the Ayurvedic pulse/constitution each nakshatra carries.</summary>
    private static readonly string[] NakshatraNadis =
    [
        "Vata", "Pitta", "Kapha", "Kapha", "Pitta", "Vata", "Vata", "Pitta",
        "Kapha", "Kapha", "Pitta", "Vata", "Vata", "Pitta", "Kapha", "Kapha",
        "Pitta", "Vata", "Vata", "Pitta", "Kapha", "Kapha", "Pitta", "Vata",
        "Vata", "Pitta", "Kapha"
    ];

    /// <summary>Gana — temperament category (Deva/Manushya/Rakshasa).</summary>
    private static readonly string[] NakshatraGanas =
    [
        "Deva", "Manushya", "Rakshasa", "Manushya", "Deva", "Manushya", "Deva", "Deva",
        "Rakshasa", "Rakshasa", "Manushya", "Manushya", "Deva", "Rakshasa", "Deva", "Rakshasa",
        "Deva", "Rakshasa", "Rakshasa", "Manushya", "Manushya", "Deva", "Rakshasa", "Rakshasa",
        "Manushya", "Manushya", "Deva"
    ];

    /// <summary>Ruling deity of each nakshatra — central to Vedic symbolism.</summary>
    private static readonly string[] NakshatraDeities =
    [
        "Ashwini Kumaras", "Yama", "Agni", "Brahma",
        "Soma (Moon)", "Rudra", "Aditi", "Brihaspati",
        "Sarpa (Nagas)", "Pitris (Ancestors)", "Bhaga", "Aryaman",
        "Savitr", "Vishwakarma", "Vayu", "Indra-Agni",
        "Mitra", "Indra", "Nirriti", "Apas (Waters)",
        "Vishvedevas", "Vishnu", "Vasus", "Varuna",
        "Aja Ekapada", "Ahir Budhnya", "Pushan"
    ];

    /// <summary>Ruling planet (dasha lord) of each nakshatra — standard Vimshottari order.</summary>
    private static readonly string[] NakshatraLords =
    [
        "Ketu", "Venus", "Sun", "Moon", "Mars", "Rahu", "Jupiter", "Saturn", "Mercury",
        "Ketu", "Venus", "Sun", "Moon", "Mars", "Rahu", "Jupiter", "Saturn", "Mercury",
        "Ketu", "Venus", "Sun", "Moon", "Mars", "Rahu", "Jupiter", "Saturn", "Mercury"
    ];

    public static string GetNakshatraYoni(int index) => NakshatraYonis[index];
    public static string GetNakshatraNadi(int index) => NakshatraNadis[index];
    public static string GetNakshatraGana(int index) => NakshatraGanas[index];
    public static string GetNakshatraDeity(int index) => NakshatraDeities[index];
    public static string GetNakshatraLord(int index) => NakshatraLords[index];

    /// <summary>Which of the 4 padas (quarters) of a nakshatra the longitude falls in. 1-indexed.</summary>
    public static int GetPada(double siderealLongitude)
    {
        var withinNakshatra = siderealLongitude % (360.0 / 27);
        return (int)(withinNakshatra / ((360.0 / 27) / 4)) + 1;
    }

    /// <summary>Degree within the current rashi (0-29.99).</summary>
    public static double GetDegreeInRashi(double siderealLongitude) => siderealLongitude % 30;

    /// <summary>
    /// Navamsa (D9) sign index for a given sidereal longitude. Each 30° sign is
    /// divided into 9 navamsas of 3°20' each. The starting navamsa sign follows
    /// the classical rule based on sign modality:
    /// - Movable signs (Mesha, Karka, Tula, Makara): start from the sign itself
    /// - Fixed signs (Vrishabha, Simha, Vrischika, Kumbha): start from the 9th
    /// - Dual signs (Mithuna, Kanya, Dhanu, Meena): start from the 5th
    /// Returns a rashi index 0-11.
    /// </summary>
    public static int GetNavamsaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi * 9 / 30); // 0..8 — which navamsa within the sign
        var startingSign = (rashiIdx % 3) switch
        {
            0 => rashiIdx,                     // movable — start from itself
            1 => (rashiIdx + 8) % 12,          // fixed — 9th from itself
            _ => (rashiIdx + 4) % 12           // dual — 5th from itself
        };
        return (startingSign + segment) % 12;
    }

    /// <summary>
    /// True when a planet sits in the cusp zone — last 1° or first 1° of its sign.
    /// Classically treated as a weak position (sandhi dosha).
    /// </summary>
    public static bool IsInSandhi(double degreeInRashi)
        => degreeInRashi < 1.0 || degreeInRashi >= 29.0;

    /// <summary>
    /// Dasamsa (D10) sign index — career, reputation, public life. Each 30°
    /// sign is divided into 10 sections of 3° each. Starting-sign rule:
    /// - Odd signs (Mesha, Mithuna, Simha, Tula, Dhanu, Kumbha): start from
    ///   the sign itself.
    /// - Even signs (Vrishabha, Karka, Kanya, Vrischika, Makara, Meena): start
    ///   from the 9th from the sign.
    /// Returns a rashi index 0-11.
    /// </summary>
    public static int GetDasamsaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi / 3.0); // 0..9
        var startingSign = rashiIdx % 2 == 0
            ? rashiIdx                 // odd sign (by Jyotish polarity) — start from itself
            : (rashiIdx + 8) % 12;     // even sign — start from 9th
        return (startingSign + segment) % 12;
    }

    /// <summary>
    /// Dvadasamsa (D12) sign index — parents, ancestry, family of origin.
    /// Each 30° sign is divided into 12 sections of 2.5° each. Starting sign
    /// is always the sign itself, regardless of polarity.
    /// Returns a rashi index 0-11.
    /// </summary>
    public static int GetDvadasamsaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi / 2.5); // 0..11
        return (rashiIdx + segment) % 12;
    }

    /// <summary>
    /// Drekkana (D3) — siblings, courage, temperament. 3 sections of 10°
    /// per sign. 1st decan starts from the sign itself, 2nd from the 5th,
    /// 3rd from the 9th (kendras/trikonas pattern).
    /// </summary>
    public static int GetDrekkanaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi / 10.0); // 0..2
        var offset = segment * 4; // 0, 4, 8 — same / 5th / 9th from sign
        return (rashiIdx + offset) % 12;
    }

    /// <summary>
    /// Chaturthamsa (D4) — home, property, fortune. 4 sections of 7.5°
    /// per sign. Each quarter starts from the 1st, 4th, 7th, and 10th
    /// sign from itself (the kendras).
    /// </summary>
    public static int GetChaturthamsaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi / 7.5); // 0..3
        var offset = segment * 3; // 0, 3, 6, 9 — the four kendras
        return (rashiIdx + offset) % 12;
    }

    /// <summary>
    /// Saptamsa (D7) — children, creative progeny. 7 sections of ~4.286°
    /// per sign. Odd signs start the 7 from themselves; even signs start
    /// from the 7th sign (opposite).
    /// </summary>
    public static int GetSaptamsaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi * 7.0 / 30.0); // 0..6
        var startingSign = rashiIdx % 2 == 0
            ? rashiIdx                  // odd sign (by Jyotish polarity) → start from self
            : (rashiIdx + 6) % 12;      // even sign → start from 7th (opposite)
        return (startingSign + segment) % 12;
    }

    /// <summary>
    /// Shodasamsa (D16, Kalamsha) — vehicles, comforts, conveyances.
    /// 16 sections of 1.875° per sign. Starting sign depends on sign modality:
    /// Movable → Mesha (0), Fixed → Simha (4), Dual → Dhanu (8).
    /// </summary>
    public static int GetShodasamsaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi / 1.875); // 0..15
        var startingSign = (rashiIdx % 3) switch
        {
            0 => 0,   // movable → Mesha
            1 => 4,   // fixed → Simha
            _ => 8    // dual → Dhanu
        };
        return (startingSign + segment) % 12;
    }

    /// <summary>
    /// Vimsamsa (D20) — spiritual progress, devotion, inner practice.
    /// 20 sections of 1.5° per sign. Starting sign depends on modality:
    /// Movable → Mesha (0), Fixed → Dhanu (8), Dual → Simha (4).
    /// </summary>
    public static int GetVimsamsaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi / 1.5); // 0..19
        var startingSign = (rashiIdx % 3) switch
        {
            0 => 0,   // movable → Mesha
            1 => 8,   // fixed → Dhanu
            _ => 4    // dual → Simha
        };
        return (startingSign + segment) % 12;
    }

    /// <summary>
    /// Chaturvimsamsa (D24, Siddhamsa) — education, learning, knowledge.
    /// 24 sections of 1.25° per sign. Odd signs start from Simha (Sun's sign),
    /// even signs start from Karka (Moon's sign).
    /// </summary>
    public static int GetChaturvimsamsaRashi(double siderealLongitude)
    {
        var rashiIdx = GetRashiIndex(siderealLongitude);
        var degInRashi = siderealLongitude % 30;
        var segment = (int)(degInRashi / 1.25); // 0..23
        var startingSign = rashiIdx % 2 == 0
            ? 4     // odd sign → Simha
            : 3;    // even sign → Karka
        return (startingSign + segment) % 12;
    }

    // Deep-exaltation peak degrees (parama uccha) per planet, in the degree
    // within the exaltation sign. Moon peaks at Taurus 3°, Sun at Aries 10°, etc.
    // Within ±3° of the peak → "deep_exalted"; otherwise just "exalted".
    private const double DeepExaltationTolerance = 3.0;
    private static readonly Dictionary<string, double> DeepExaltationDegree = new()
    {
        ["Sun"] = 10.0,      // Mesha 10°
        ["Moon"] = 3.0,      // Vrishabha 3°
        ["Mars"] = 28.0,     // Makara 28°
        ["Mercury"] = 15.0,  // Kanya 15°
        ["Jupiter"] = 5.0,   // Karka 5°
        ["Venus"] = 27.0,    // Meena 27°
        ["Saturn"] = 20.0    // Tula 20°
    };

    // Moolatrikona ranges — (rashiIndex, startDeg, endDeg). Within this range
    // the planet has a dignity tier between "own_sign" and "exalted".
    // Classical ranges from Phaladeepika / BPHS.
    private static readonly Dictionary<string, (int Rashi, double Start, double End)> MoolatrikonaRange = new()
    {
        ["Sun"] = (4, 0, 20),        // Simha 0–20°
        ["Moon"] = (1, 4, 30),       // Vrishabha 4–30° (Moon's moolatrikona is NOT in its own sign Karka)
        ["Mars"] = (0, 0, 12),       // Mesha 0–12°
        ["Mercury"] = (5, 16, 20),   // Kanya 16–20° (a narrow strip within its exaltation sign)
        ["Jupiter"] = (8, 0, 10),    // Dhanu 0–10°
        ["Venus"] = (6, 0, 15),      // Tula 0–15°
        ["Saturn"] = (10, 0, 20)     // Kumbha 0–20°
    };

    /// <summary>
    /// Computes the tropical ecliptic longitude of the Ascendant (Lagna) — the point of
    /// the ecliptic rising on the eastern horizon at birth. Requires birth time and
    /// geographic coordinates. Convert to sidereal with ToSidereal for the rashi.
    /// </summary>
    public static double GetTropicalAscendant(DateTime birthUtc, double latitudeDeg, double longitudeDeg)
    {
        // Greenwich Mean Sidereal Time in hours, from the standard formula
        // (Meeus, Astronomical Algorithms, ch. 12)
        var jd = ToJulianDay(birthUtc);
        var T = (jd - 2451545.0) / 36525.0;
        var gmstDeg = 280.46061837
                      + 360.98564736629 * (jd - 2451545.0)
                      + 0.000387933 * T * T
                      - T * T * T / 38710000.0;
        gmstDeg = Normalize(gmstDeg);

        var lstDeg = Normalize(gmstDeg + longitudeDeg);
        var lstRad = lstDeg * Math.PI / 180.0;
        var latRad = latitudeDeg * Math.PI / 180.0;
        const double obliquityDeg = 23.4367; // mean obliquity of ecliptic, good enough here
        var eps = obliquityDeg * Math.PI / 180.0;

        // Ascendant formula (Meeus ch. 12). The raw atan2 can land on the
        // descendant (west) instead of the ascendant (east); flipping both
        // components puts us on the rising side.
        var y = Math.Cos(lstRad);
        var x = -(Math.Sin(lstRad) * Math.Cos(eps) + Math.Tan(latRad) * Math.Sin(eps));
        var asc = Math.Atan2(y, x) * 180.0 / Math.PI;
        return Normalize(asc);
    }

    private static double ToJulianDay(DateTime utc)
    {
        // Meeus formula for Julian Day Number from Gregorian UTC
        int y = utc.Year, m = utc.Month;
        if (m <= 2) { y -= 1; m += 12; }
        var a = y / 100;
        var b = 2 - a + a / 4;
        var dayFrac = utc.Day + (utc.Hour + utc.Minute / 60.0 + utc.Second / 3600.0) / 24.0;
        return Math.Floor(365.25 * (y + 4716)) + Math.Floor(30.6001 * (m + 1)) + dayFrac + b - 1524.5;
    }

    /// <summary>
    /// Returns the planet's dignity given its sign AND degree in that sign.
    /// Degree-aware so that within the exaltation sign we distinguish
    /// "deep_exalted" (within ±3° of peak) from ordinary "exalted", and
    /// within the own/moolatrikona sign we surface the moolatrikona tier.
    ///
    /// Priority order (strongest first): deep_exalted → exalted →
    /// moolatrikona → own_sign → debilitated → neutral.
    ///
    /// Edge case (Mercury): Kanya 0–15° is Mercury's exaltation zone (with
    /// peak at 15°), 16–20° is moolatrikona, 20–30° is own_sign. This
    /// overlapping-sign case is handled explicitly.
    ///
    /// Rahu/Ketu exaltation follows the Parashara tradition used elsewhere
    /// (Rahu exalted in Vrishabha, Ketu in Vrischika). Rahu/Ketu do not have
    /// deep-exalt / moolatrikona definitions in this tradition.
    /// </summary>
    public static string GetDignity(string planet, int rashiIndex, double degreeInRashi)
    {
        // Check exaltation first (with deep-exalt refinement)
        var exaltSign = planet switch
        {
            "Sun" => 0, "Moon" => 1, "Mars" => 9, "Mercury" => 5,
            "Jupiter" => 3, "Venus" => 11, "Saturn" => 6,
            "Rahu" => 1, "Ketu" => 7,
            _ => -1
        };
        if (exaltSign == rashiIndex)
        {
            // Mercury's Kanya has well-documented overlapping zones with own_sign
            // — handle specifically because the classical sources are explicit:
            // 0–15° exalted (peak at 15°), 16–20° moolatrikona, 20–30° own_sign.
            if (planet == "Mercury")
            {
                if (degreeInRashi >= 16 && degreeInRashi < 20) return "moolatrikona";
                if (degreeInRashi >= 20) return "own_sign";
            }

            // Deep exaltation — narrow peak takes highest priority
            if (DeepExaltationDegree.TryGetValue(planet, out var peak)
                && Math.Abs(degreeInRashi - peak) <= DeepExaltationTolerance)
            {
                return "deep_exalted";
            }

            // For other planets (notably Moon whose moolatrikona overlaps with
            // its exaltation sign) we let exaltation win in the exaltation sign.
            // This matches the most common teaching and keeps the label users expect.
            return "exalted";
        }

        // Check debilitation
        var debilSign = planet switch
        {
            "Sun" => 6, "Moon" => 7, "Mars" => 3, "Mercury" => 11,
            "Jupiter" => 9, "Venus" => 5, "Saturn" => 0,
            "Rahu" => 7, "Ketu" => 1,
            _ => -1
        };
        if (debilSign == rashiIndex) return "debilitated";

        // Check own sign — and within that, moolatrikona sub-range
        var ownSigns = planet switch
        {
            "Sun" => new[] { 4 },
            "Moon" => new[] { 3 },
            "Mars" => new[] { 0, 7 },
            "Mercury" => new[] { 2, 5 },    // Kanya handled above since it's also exalt
            "Jupiter" => new[] { 8, 11 },
            "Venus" => new[] { 1, 6 },
            "Saturn" => new[] { 9, 10 },
            _ => Array.Empty<int>()
        };
        if (ownSigns.Contains(rashiIndex))
        {
            if (MoolatrikonaRange.TryGetValue(planet, out var mt)
                && mt.Rashi == rashiIndex
                && degreeInRashi >= mt.Start && degreeInRashi < mt.End)
            {
                return "moolatrikona";
            }
            return "own_sign";
        }

        // Moolatrikona can live in a non-own-sign (Moon's moolatrikona is in
        // Vrishabha, which is not Moon's own sign). Check that case too.
        if (MoolatrikonaRange.TryGetValue(planet, out var mtRange)
            && mtRange.Rashi == rashiIndex
            && degreeInRashi >= mtRange.Start && degreeInRashi < mtRange.End)
        {
            // But only if we haven't already classified this sign as exalted above.
            // (If rashiIndex == exaltSign, we returned earlier.)
            return "moolatrikona";
        }

        return "neutral";
    }

    /// <summary>Compute the house number (1-12) using the Whole-Sign system, the standard
    /// approach in Vedic astrology. The entire sign containing the ascendant becomes H1,
    /// the next sign H2, and so on — regardless of the ascendant's exact degree within
    /// its sign. Both longitudes must be in sidereal frame.</summary>
    public static int GetHouse(double bodyLongitude, double ascendantLongitude)
    {
        var ascRashi = GetRashiIndex(ascendantLongitude);
        var bodyRashi = GetRashiIndex(bodyLongitude);
        return ((bodyRashi - ascRashi + 12) % 12) + 1;
    }

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

    public static double GetAyanamsa(DateTime date)
    {
        var yearsSinceJ2000 = (date - new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc)).TotalDays / 365.25;
        return AyanamsaJ2000 + AyanamsaRate * yearsSinceJ2000;
    }

    public static double GetTropicalSunLongitude(DateTime date)
    {
        var daysSinceJ2000 = (date - new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc)).TotalDays;
        var L = (280.46646 + 0.9856474 * daysSinceJ2000) % 360;
        var M = (357.52911 + 0.9856003 * daysSinceJ2000) % 360;
        var MRad = M * Math.PI / 180;
        var C = 1.9146 * Math.Sin(MRad) + 0.02 * Math.Sin(2 * MRad);
        var sunLong = (L + C) % 360;
        return sunLong < 0 ? sunLong + 360 : sunLong;
    }

    public static double GetTropicalMoonLongitude(DateTime date)
    {
        var daysSinceJ2000 = (date - new DateTime(2000, 1, 1, 12, 0, 0, DateTimeKind.Utc)).TotalDays;
        var T = daysSinceJ2000 / 36525.0;

        var Lp = Normalize(218.3165 + 481267.8813 * T);
        var D = Normalize(297.8502 + 445267.1115 * T);
        var M = Normalize(357.5291 + 35999.0503 * T);
        var Mp = Normalize(134.9634 + 477198.8676 * T);
        var F = Normalize(93.2720 + 483202.0175 * T);

        var DRad = D * Math.PI / 180;
        var MRad = M * Math.PI / 180;
        var MpRad = Mp * Math.PI / 180;
        var FRad = F * Math.PI / 180;

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

    public static double ToSidereal(double tropicalLongitude, DateTime date)
    {
        var sidereal = tropicalLongitude - GetAyanamsa(date);
        return sidereal < 0 ? sidereal + 360 : sidereal % 360;
    }

    public static int GetRashiIndex(double siderealLongitude) => (int)(siderealLongitude / 30) % 12;

    public static int GetNakshatraIndex(double siderealLongitude) => (int)(siderealLongitude / (360.0 / 27)) % 27;

    public static string GetRashi(int index) => $"{Rashis[index]} ({RashiEnglish[index]})";

    public static (string Name, string Quality) GetNakshatra(int index) => (Nakshatras[index], NakshatraQualities[index]);

    // Vimshottari Dasha — the 120-year planetary period system.
    // Sequence and durations (years): Ketu 7, Venus 20, Sun 6, Moon 10, Mars 7,
    // Rahu 18, Jupiter 16, Saturn 19, Mercury 17. The lord of your birth nakshatra
    // rules the first Mahadasha; the cycle proceeds from there.
    private static readonly (string Name, int Years)[] DashaSequence =
    [
        ("Ketu", 7),
        ("Venus", 20),
        ("Sun", 6),
        ("Moon", 10),
        ("Mars", 7),
        ("Rahu", 18),
        ("Jupiter", 16),
        ("Saturn", 19),
        ("Mercury", 17)
    ];

    public record DashaInfo(
        string Mahadasha,
        string Antardasha,
        DateTime MahadashaStart,
        DateTime MahadashaEnd,
        DateTime AntardashaStart,
        DateTime AntardashaEnd);

    /// <summary>
    /// Computes the user's current Mahadasha and Antardasha based on birth moon
    /// position (Vimshottari system). Requires birth date AND time.
    /// </summary>
    public static DashaInfo GetCurrentDasha(DateTime birthDateTime, DateTime now)
    {
        var moonSidereal = ToSidereal(GetTropicalMoonLongitude(birthDateTime), birthDateTime);
        var nakshatraIndex = GetNakshatraIndex(moonSidereal);
        var lordIndex = nakshatraIndex % 9;

        // Fraction of birth nakshatra already traversed at birth
        var nakshatraStart = nakshatraIndex * (360.0 / 27);
        var elapsedFraction = (moonSidereal - nakshatraStart) / (360.0 / 27);
        elapsedFraction = Math.Clamp(elapsedFraction, 0, 1);

        // Walk through mahadashas until we find the one containing `now`
        var currentIdx = lordIndex;
        var mahadashaYears = DashaSequence[currentIdx].Years;
        var mahadashaStart = birthDateTime;
        var mahadashaEnd = birthDateTime.AddDays(mahadashaYears * (1 - elapsedFraction) * 365.25);

        while (now >= mahadashaEnd)
        {
            mahadashaStart = mahadashaEnd;
            currentIdx = (currentIdx + 1) % 9;
            mahadashaYears = DashaSequence[currentIdx].Years;
            mahadashaEnd = mahadashaStart.AddDays(mahadashaYears * 365.25);
        }

        var mahadashaName = DashaSequence[currentIdx].Name;

        // Find antardasha within the mahadasha. The antardasha sequence begins
        // with the mahadasha lord itself, then cycles through the standard order.
        // Each antardasha's duration is proportional: mahaYears * subYears / 120.
        var subStart = mahadashaStart;
        var subEnd = subStart;
        var subName = mahadashaName;

        for (var i = 0; i < 9; i++)
        {
            var subIdx = (currentIdx + i) % 9;
            var subYears = DashaSequence[subIdx].Years;
            var subDays = mahadashaYears * subYears / 120.0 * 365.25;
            subEnd = subStart.AddDays(subDays);
            if (now < subEnd)
            {
                subName = DashaSequence[subIdx].Name;
                break;
            }
            subStart = subEnd;
        }

        return new DashaInfo(
            Mahadasha: mahadashaName,
            Antardasha: subName,
            MahadashaStart: mahadashaStart,
            MahadashaEnd: mahadashaEnd,
            AntardashaStart: subStart,
            AntardashaEnd: subEnd);
    }

    public static (string Tithi, string TithiQuality, string Vara, string VaraDeity, string Yoga, string Nakshatra, string NakshatraQuality) GetPanchang(DateTime date)
    {
        var sunSidereal = ToSidereal(GetTropicalSunLongitude(date), date);
        var moonSidereal = ToSidereal(GetTropicalMoonLongitude(date), date);

        var elongation = moonSidereal - sunSidereal;
        if (elongation < 0) elongation += 360;
        var tithiIndex = (int)(elongation / 12) % 30;
        var tithiName = Tithis[tithiIndex % 15];
        var paksha = tithiIndex < 15 ? "Shukla" : "Krishna";
        var tithiQuality = TithiQualities[tithiIndex % 15];

        var varaIndex = (int)date.DayOfWeek;
        var vara = Varas[varaIndex];
        var varaDeity = VaraDeities[varaIndex];

        var yogaValue = (sunSidereal + moonSidereal) % 360;
        var yogaIndex = (int)(yogaValue / (360.0 / 27)) % 27;
        var yoga = Yogas[yogaIndex];

        var nakshatraIndex = GetNakshatraIndex(moonSidereal);
        var (nakshatraName, nakshatraQuality) = GetNakshatra(nakshatraIndex);

        return ($"{paksha} {tithiName}", tithiQuality, vara, varaDeity, yoga, nakshatraName, nakshatraQuality);
    }
}
