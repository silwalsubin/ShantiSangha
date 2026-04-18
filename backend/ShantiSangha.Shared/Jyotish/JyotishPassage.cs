using System.Text.Json.Serialization;

namespace ShantiSangha.Shared.Jyotish;

/// <summary>
/// A passage of traditional Vedic interpretation keyed by chart signatures
/// (e.g. "saturn_in_h7", "jupiter_mahadasha"). Loaded from a curated
/// corpus of classical Jyotish sources. Used as invisible context for
/// AI-generated content (reflections, readings, whispers, chat).
/// </summary>
public record JyotishPassage
{
    [JsonPropertyName("id")] public string Id { get; init; } = "";
    [JsonPropertyName("signature_type")] public string SignatureType { get; init; } = "";
    [JsonPropertyName("signatures")] public List<string> Signatures { get; init; } = [];
    [JsonPropertyName("title")] public string Title { get; init; } = "";
    [JsonPropertyName("content")] public string Content { get; init; } = "";
    [JsonPropertyName("themes")] public List<string> Themes { get; init; } = [];
    [JsonPropertyName("polarity")] public string Polarity { get; init; } = "mixed";
    [JsonPropertyName("source")] public string Source { get; init; } = "";
    [JsonPropertyName("scope")] public string Scope { get; init; } = "lifetime";
}
