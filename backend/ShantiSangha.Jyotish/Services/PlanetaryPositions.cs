namespace ShantiSangha.Jyotish.Services;

/// <summary>
/// Approximate geocentric ecliptic longitudes for the classical Vedic planets
/// and the lunar nodes. Uses Paul Schlyter's simplified formulas
/// (https://stjarnhimlen.se/comp/ppcomp.html). Accuracy ~1-2 degrees,
/// sufficient for chart display, not for professional astrology.
/// </summary>
public static class PlanetaryPositions
{
    private static readonly DateTime Epoch = new(1999, 12, 31, 0, 0, 0, DateTimeKind.Utc);

    private const double DegToRad = Math.PI / 180.0;
    private const double RadToDeg = 180.0 / Math.PI;

    public static double GetTropicalMercuryLongitude(DateTime date) => GeocentricLongitude(Planet.Mercury, DaysSinceEpoch(date));

    public static double GetTropicalVenusLongitude(DateTime date) => GeocentricLongitude(Planet.Venus, DaysSinceEpoch(date));

    public static double GetTropicalMarsLongitude(DateTime date) => GeocentricLongitude(Planet.Mars, DaysSinceEpoch(date));

    public static double GetTropicalJupiterLongitude(DateTime date) => GeocentricLongitude(Planet.Jupiter, DaysSinceEpoch(date));

    public static double GetTropicalSaturnLongitude(DateTime date) => GeocentricLongitude(Planet.Saturn, DaysSinceEpoch(date));

    public static double GetTropicalRahuLongitude(DateTime date)
    {
        var d = DaysSinceEpoch(date);
        return Normalize(125.1228 - 0.0529538083 * d);
    }

    public static double GetTropicalKetuLongitude(DateTime date) => Normalize(GetTropicalRahuLongitude(date) + 180.0);

    private enum Planet { Mercury, Venus, Earth, Mars, Jupiter, Saturn }

    private static double DaysSinceEpoch(DateTime date)
    {
        var utc = date.Kind == DateTimeKind.Utc ? date : DateTime.SpecifyKind(date, DateTimeKind.Utc);
        return (utc - Epoch).TotalDays;
    }

    private static double GeocentricLongitude(Planet planet, double d)
    {
        var (xp, yp, zp) = HeliocentricEcliptic(planet, d);
        var (xe, ye, ze) = HeliocentricEcliptic(Planet.Earth, d);

        var xg = xp - xe;
        var yg = yp - ye;
        // zg not needed for longitude
        _ = zp - ze;

        var lon = Math.Atan2(yg, xg) * RadToDeg;
        return Normalize(lon);
    }

    private static (double X, double Y, double Z) HeliocentricEcliptic(Planet planet, double d)
    {
        var (N, i, w, a, e, M) = OrbitalElements(planet, d);

        var MRad = M * DegToRad;
        var eRad = e; // eccentricity is dimensionless
        // Solve Kepler's equation with a single-step correction (adequate for e < 0.2)
        var E = M + RadToDeg * eRad * Math.Sin(MRad) * (1 + eRad * Math.Cos(MRad));
        // One Newton refinement for Mercury/Mars which have larger e
        var ERad = E * DegToRad;
        var dE = (E - RadToDeg * eRad * Math.Sin(ERad) - M) / (1 - eRad * Math.Cos(ERad));
        E -= dE;
        ERad = E * DegToRad;

        var xv = a * (Math.Cos(ERad) - eRad);
        var yv = a * (Math.Sqrt(1 - eRad * eRad) * Math.Sin(ERad));

        var v = Math.Atan2(yv, xv);
        var r = Math.Sqrt(xv * xv + yv * yv);

        var NRad = N * DegToRad;
        var iRad = i * DegToRad;
        var wRad = w * DegToRad;

        var cosN = Math.Cos(NRad);
        var sinN = Math.Sin(NRad);
        var cosI = Math.Cos(iRad);
        var sinI = Math.Sin(iRad);
        var cosVW = Math.Cos(v + wRad);
        var sinVW = Math.Sin(v + wRad);

        var x = r * (cosN * cosVW - sinN * sinVW * cosI);
        var y = r * (sinN * cosVW + cosN * sinVW * cosI);
        var z = r * (sinVW * sinI);

        return (x, y, z);
    }

    // Orbital elements from Schlyter (https://stjarnhimlen.se/comp/ppcomp.html)
    // N = longitude of ascending node, i = inclination, w = argument of perihelion,
    // a = semi-major axis (AU), e = eccentricity, M = mean anomaly.
    private static (double N, double i, double w, double a, double e, double M) OrbitalElements(Planet planet, double d)
    {
        double N, i, w, a, e, M;
        switch (planet)
        {
            case Planet.Mercury:
                N = 48.3313 + 3.24587e-5 * d;
                i = 7.0047 + 5.00e-8 * d;
                w = 29.1241 + 1.01444e-5 * d;
                a = 0.387098;
                e = 0.205635 + 5.59e-10 * d;
                M = 168.6562 + 4.0923344368 * d;
                break;
            case Planet.Venus:
                N = 76.6799 + 2.46590e-5 * d;
                i = 3.3946 + 2.75e-8 * d;
                w = 54.8910 + 1.38374e-5 * d;
                a = 0.723330;
                e = 0.006773 - 1.302e-9 * d;
                M = 48.0052 + 1.6021302244 * d;
                break;
            case Planet.Earth:
                // Earth's orbit (= Sun's apparent orbit reflected). Elements from Schlyter's Sun section.
                N = 0.0;
                i = 0.0;
                w = 282.9404 + 4.70935e-5 * d;
                a = 1.000000;
                e = 0.016709 - 1.151e-9 * d;
                M = 356.0470 + 0.9856002585 * d;
                break;
            case Planet.Mars:
                N = 49.5574 + 2.11081e-5 * d;
                i = 1.8497 - 1.78e-8 * d;
                w = 286.5016 + 2.92961e-5 * d;
                a = 1.523688;
                e = 0.093405 + 2.516e-9 * d;
                M = 18.6021 + 0.5240207766 * d;
                break;
            case Planet.Jupiter:
                N = 100.4542 + 2.76854e-5 * d;
                i = 1.3030 - 1.557e-7 * d;
                w = 273.8777 + 1.64505e-5 * d;
                a = 5.20256;
                e = 0.048498 + 4.469e-9 * d;
                M = 19.8950 + 0.0830853001 * d;
                break;
            case Planet.Saturn:
                N = 113.6634 + 2.38980e-5 * d;
                i = 2.4886 - 1.081e-7 * d;
                w = 339.3939 + 2.97661e-5 * d;
                a = 9.55475;
                e = 0.055546 - 9.499e-9 * d;
                M = 316.9670 + 0.0334442282 * d;
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(planet));
        }

        return (Normalize(N), i, Normalize(w), a, e, Normalize(M));
    }

    private static double Normalize(double degrees)
    {
        var result = degrees % 360;
        return result < 0 ? result + 360 : result;
    }
}
