using System.Collections.Concurrent;
using System.Reflection;
using System.Text.Json;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Jyotish.Services;

/// <summary>
/// Loads the Jyotish corpus once (from embedded JSON resource) and serves
/// passage lookups by signature. Indexed at construction for O(1) retrieval.
/// </summary>
public class JyotishKnowledgeService : IJyotishKnowledgeService
{
    private readonly List<JyotishPassage> _allPassages;
    private readonly ConcurrentDictionary<string, List<JyotishPassage>> _bySignature;

    public int TotalPassages => _allPassages.Count;

    public JyotishKnowledgeService()
    {
        _allPassages = LoadCorpus();
        _bySignature = new ConcurrentDictionary<string, List<JyotishPassage>>();

        foreach (var p in _allPassages)
        {
            foreach (var sig in p.Signatures)
            {
                var key = Normalize(sig);
                var list = _bySignature.GetOrAdd(key, _ => new List<JyotishPassage>());
                list.Add(p);
            }
        }
    }

    public IReadOnlyList<JyotishPassage> GetPassages(IEnumerable<string> signatures)
    {
        var results = new List<JyotishPassage>();
        var seen = new HashSet<string>();
        foreach (var sig in signatures)
        {
            if (_bySignature.TryGetValue(Normalize(sig), out var matches))
            {
                foreach (var m in matches)
                {
                    if (seen.Add(m.Id)) results.Add(m);
                }
            }
        }
        return results;
    }

    public IReadOnlyList<string> ComputeSignaturesForBirth(
        DateOnly birthDate,
        TimeOnly? birthTime,
        double? latitude,
        double? longitude,
        DateTime? now = null)
        => ChartSignatures.ComputeNatalSignatures(birthDate, birthTime, latitude, longitude, now);

    private static string Normalize(string s) => s.Trim().ToLowerInvariant();

    private static List<JyotishPassage> LoadCorpus()
    {
        var asm = Assembly.GetExecutingAssembly();
        var resourceName = asm.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith("JyotishCorpus.json", StringComparison.OrdinalIgnoreCase));

        if (resourceName is null)
            throw new InvalidOperationException(
                "JyotishCorpus.json not found as embedded resource. " +
                "Confirm the .csproj includes <EmbeddedResource Include=\"Data\\JyotishCorpus.json\" />.");

        using var stream = asm.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException("Failed to open JyotishCorpus.json stream.");
        using var reader = new StreamReader(stream);
        var json = reader.ReadToEnd();

        var passages = JsonSerializer.Deserialize<List<JyotishPassage>>(json)
            ?? throw new InvalidOperationException("JyotishCorpus.json deserialized to null.");
        return passages;
    }
}
