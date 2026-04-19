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
    IProfileQueryService profileQuery,
    IJyotishKnowledgeService knowledge) : ControllerBase
{
    /// <summary>
    /// Looks up the first passage matching a signature in a pre-fetched dictionary.
    /// GetChart fetches all candidate signatures in one DB round-trip, builds this
    /// dict, then calls this per chart element. Avoids N+1 queries on the corpus.
    /// </summary>
    private static object? InterpretationFor(
        string signature,
        IReadOnlyDictionary<string, ShantiSangha.Shared.Jyotish.JyotishPassage> bySignature)
    {
        if (!bySignature.TryGetValue(signature.Trim().ToLowerInvariant(), out var p))
            return null;
        return new
        {
            Content = p.Content,
            Source = p.Source,
            Polarity = p.Polarity,
            Themes = p.Themes
        };
    }

    /// <summary>Normalize "Mithuna (Gemini)" → "mithuna" for signature lookup.</summary>
    private static string NormalizeRashi(string rashiLabel)
    {
        var sanskrit = rashiLabel.Split(' ')[0];
        return sanskrit.Trim().ToLowerInvariant();
    }

    /// <summary>Normalize "Purva Phalguni" → "purva_phalguni" for signature lookup.</summary>
    private static string NormalizeNakshatra(string nakshatraName)
        => nakshatraName.Trim().ToLowerInvariant().Replace(' ', '_');
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

        // Resolve local birth time → UTC using IANA timezone from lat/lon.
        // This handles political timezone offsets + DST correctly.
        var birthDateTime = BirthTimeResolver.ResolveBirthUtc(
            birthDate, parsedTime, latitude, longitude);

        // Nakshatra attributes (from moon's sidereal position at birth)
        var moonTropical = VedicCalendar.GetTropicalMoonLongitude(birthDateTime);
        var moonSidereal = VedicCalendar.ToSidereal(moonTropical, birthDateTime);
        var moonNakshatraIdx = VedicCalendar.GetNakshatraIndex(moonSidereal);
        var (moonNakshatraName, moonNakshatraQuality) = VedicCalendar.GetNakshatra(moonNakshatraIdx);
        var moonPada = VedicCalendar.GetPada(moonSidereal);

        // Nakshatra attrs — Interpretation attached later after the batch passage fetch.
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
            var ascRashiLabel = VedicCalendar.GetRashi(ascRashiIdx);
            lagna = new
            {
                Rashi = ascRashiLabel,
                Degree = Math.Round(VedicCalendar.GetDegreeInRashi(ascendantSidereal.Value), 2),
                Nakshatra = ascNakName,
                NakshatraQuality = ascNakQuality,
                Pada = VedicCalendar.GetPada(ascendantSidereal.Value)
                // Interpretation attached later after the batch passage fetch.
            };
        }

        // Sun's tropical longitude is needed for combustion checks below.
        var sunTropicalForCombustion = VedicCalendar.GetTropicalSunLongitude(birthDateTime);

        // Pass 1: compute planet data WITHOUT interpretations (so we can collect
        // all candidate signatures first and batch-fetch passages in one DB call).
        var planetRows = planetLongitudes.Select(p =>
        {
            var sidereal = VedicCalendar.ToSidereal(p.Tropical, birthDateTime);
            var rashiIdx = VedicCalendar.GetRashiIndex(sidereal);
            var degInRashi = VedicCalendar.GetDegreeInRashi(sidereal);
            var nakIdx = VedicCalendar.GetNakshatraIndex(sidereal);
            var (nakName, nakQuality) = VedicCalendar.GetNakshatra(nakIdx);
            int? house = ascendantSidereal.HasValue
                ? VedicCalendar.GetHouse(sidereal, ascendantSidereal.Value)
                : (int?)null;

            var navamsaIdx = VedicCalendar.GetNavamsaRashi(sidereal);
            var rashiLabel = VedicCalendar.GetRashi(rashiIdx);

            return new
            {
                Name = p.Name,
                Tropical = p.Tropical,
                Sidereal = sidereal,
                RashiIdx = rashiIdx,
                RashiLabel = rashiLabel,
                DegInRashi = degInRashi,
                NakName = nakName,
                NakQuality = nakQuality,
                Pada = VedicCalendar.GetPada(sidereal),
                House = house,
                NavamsaRashi = VedicCalendar.GetRashi(navamsaIdx),
                Vargottama = navamsaIdx == rashiIdx,
                DrekkanaRashi = VedicCalendar.GetRashi(VedicCalendar.GetDrekkanaRashi(sidereal)),
                ChaturthamsaRashi = VedicCalendar.GetRashi(VedicCalendar.GetChaturthamsaRashi(sidereal)),
                SaptamsaRashi = VedicCalendar.GetRashi(VedicCalendar.GetSaptamsaRashi(sidereal)),
                DasamsaRashi = VedicCalendar.GetRashi(VedicCalendar.GetDasamsaRashi(sidereal)),
                DvadasamsaRashi = VedicCalendar.GetRashi(VedicCalendar.GetDvadasamsaRashi(sidereal)),
                ShodasamsaRashi = VedicCalendar.GetRashi(VedicCalendar.GetShodasamsaRashi(sidereal)),
                VimsamsaRashi = VedicCalendar.GetRashi(VedicCalendar.GetVimsamsaRashi(sidereal)),
                ChaturvimsamsaRashi = VedicCalendar.GetRashi(VedicCalendar.GetChaturvimsamsaRashi(sidereal)),
                Dignity = VedicCalendar.GetDignity(p.Name, rashiIdx, degInRashi),
                Sandhi = VedicCalendar.IsInSandhi(degInRashi),
                Retrograde = PlanetaryPositions.IsRetrograde(p.Name, birthDateTime),
                Combust = PlanetaryPositions.IsCombust(
                    p.Name, p.Tropical, sunTropicalForCombustion,
                    PlanetaryPositions.IsRetrograde(p.Name, birthDateTime))
            };
        }).ToList();

        var dasha = VedicCalendar.GetCurrentDasha(birthDateTime, DateTime.UtcNow);

        // Collect every signature we might need across the whole chart.
        var candidateSignatures = new List<string> {
            $"moon_in_{NormalizeNakshatra(moonNakshatraName)}",
            $"{dasha.Mahadasha.ToLowerInvariant()}_mahadasha"
        };
        string? lagnaRashiNormalized = null;
        if (lagna is not null)
        {
            var lagnaRashiLabel = (string)((dynamic)lagna).Rashi;
            lagnaRashiNormalized = NormalizeRashi(lagnaRashiLabel);
            candidateSignatures.Add($"lagna_in_{lagnaRashiNormalized}");
        }
        foreach (var pr in planetRows)
        {
            var planetKey = pr.Name.ToLowerInvariant();
            var rashiKey = NormalizeRashi(pr.RashiLabel);
            if (pr.House.HasValue)
            {
                candidateSignatures.Add($"{planetKey}_in_h{pr.House.Value}");
                // Compound signature — planet in house with ascendant in specific rashi.
                if (lagnaRashiNormalized is not null)
                    candidateSignatures.Add($"{planetKey}_in_h{pr.House.Value}__lagna_{lagnaRashiNormalized}");
            }
            candidateSignatures.Add($"{planetKey}_in_{rashiKey}");
        }

        // Single DB round-trip. Build an in-memory dict keyed by each signature
        // string (lowercased) to the first matching passage.
        var passages = await knowledge.GetPassagesAsync(candidateSignatures, ct);
        var bySignature = passages
            .SelectMany(p => p.Signatures.Select(sig => (Key: sig.Trim().ToLowerInvariant(), Passage: p)))
            .GroupBy(x => x.Key)
            .ToDictionary(g => g.Key, g => g.First().Passage);

        // Pass 2: build the final response, attaching interpretations from the dict.
        var planets = planetRows.Select(pr =>
        {
            var planetKey = pr.Name.ToLowerInvariant();
            var rashiKey = NormalizeRashi(pr.RashiLabel);

            // Prefer the most specific match: compound (with ascendant) → house → sign.
            object? interpretation = null;
            if (pr.House.HasValue && lagnaRashiNormalized is not null)
                interpretation = InterpretationFor(
                    $"{planetKey}_in_h{pr.House.Value}__lagna_{lagnaRashiNormalized}", bySignature);
            if (interpretation is null && pr.House.HasValue)
                interpretation = InterpretationFor($"{planetKey}_in_h{pr.House.Value}", bySignature);
            interpretation ??= InterpretationFor($"{planetKey}_in_{rashiKey}", bySignature);

            return new
            {
                Name = pr.Name,
                Rashi = pr.RashiLabel,
                Degree = Math.Round(pr.DegInRashi, 2),
                Nakshatra = pr.NakName,
                NakshatraQuality = pr.NakQuality,
                Pada = pr.Pada,
                House = pr.House,
                Dignity = pr.Dignity,
                NavamsaRashi = pr.NavamsaRashi,
                DrekkanaRashi = pr.DrekkanaRashi,
                ChaturthamsaRashi = pr.ChaturthamsaRashi,
                SaptamsaRashi = pr.SaptamsaRashi,
                DasamsaRashi = pr.DasamsaRashi,
                DvadasamsaRashi = pr.DvadasamsaRashi,
                ShodasamsaRashi = pr.ShodasamsaRashi,
                VimsamsaRashi = pr.VimsamsaRashi,
                ChaturvimsamsaRashi = pr.ChaturvimsamsaRashi,
                Vargottama = pr.Vargottama,
                Retrograde = pr.Retrograde,
                Combust = pr.Combust,
                Sandhi = pr.Sandhi,
                Interpretation = interpretation
            };
        }).ToList();

        // Re-attach nakshatra/lagna interpretations from the dict (rebuild with it).
        var nakshatraAttrsWithInterp = new
        {
            nakshatraAttrs.Name,
            nakshatraAttrs.Quality,
            nakshatraAttrs.Pada,
            nakshatraAttrs.Yoni,
            nakshatraAttrs.Nadi,
            nakshatraAttrs.Gana,
            nakshatraAttrs.Deity,
            nakshatraAttrs.Lord,
            Interpretation = InterpretationFor($"moon_in_{NormalizeNakshatra(moonNakshatraName)}", bySignature)
        };

        object? lagnaWithInterp = null;
        if (lagna is not null && lagnaRashiNormalized is not null)
        {
            var d = (dynamic)lagna;
            lagnaWithInterp = new
            {
                Rashi = (string)d.Rashi,
                Degree = (double)d.Degree,
                Nakshatra = (string)d.Nakshatra,
                NakshatraQuality = (string)d.NakshatraQuality,
                Pada = (int)d.Pada,
                Interpretation = InterpretationFor($"lagna_in_{lagnaRashiNormalized}", bySignature)
            };
        }

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
            Nakshatra = nakshatraAttrsWithInterp,
            Lagna = lagnaWithInterp,
            Planets = planets,
            Dasha = new
            {
                Mahadasha = dasha.Mahadasha,
                Antardasha = dasha.Antardasha,
                AntardashaStart = dasha.AntardashaStart.ToString("yyyy-MM-dd"),
                AntardashaEnd = dasha.AntardashaEnd.ToString("yyyy-MM-dd"),
                MahadashaStart = dasha.MahadashaStart.ToString("yyyy-MM-dd"),
                MahadashaEnd = dasha.MahadashaEnd.ToString("yyyy-MM-dd"),
                Interpretation = InterpretationFor($"{dasha.Mahadasha.ToLowerInvariant()}_mahadasha", bySignature)
            }
        });
    }
}
