using Pgvector;

namespace ShantiSangha.Jyotish.Models;

/// <summary>
/// Database entity for a source-cited Jyotish passage. Every row must carry
/// verifiable provenance (source_book, source_author, source_year, source_license)
/// so the corpus is auditable.
///
/// Distinct from ShantiSangha.Shared.Jyotish.JyotishPassage (the DTO used by
/// consumers): this entity adds the persistence and provenance concerns.
/// </summary>
public class JyotishPassageEntity
{
    public Guid Id { get; set; }

    // Canonical identifier used in DTOs (e.g. "sun_in_h1", "moon_in_mrigashirsha").
    // Unique across the corpus.
    public string PassageId { get; set; } = string.Empty;

    // --- Signature matching (for exact retrieval) ---
    public string SignatureType { get; set; } = string.Empty;
    public List<string> Signatures { get; set; } = [];

    // --- Content ---
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public List<string> Themes { get; set; } = [];
    public string Polarity { get; set; } = "mixed";
    public string Scope { get; set; } = "lifetime";

    // --- Provenance (required for every row) ---
    public string SourceBook { get; set; } = string.Empty;      // e.g. "Brihat Jataka of Varaha Mihira"
    public string SourceAuthor { get; set; } = string.Empty;    // translator name
    public int SourceYear { get; set; }                          // translation year (must be pre-1929 unless licensed)
    public string SourceLicense { get; set; } = string.Empty;   // "public_domain" | "licensed"
    public string? SourceChapter { get; set; }                   // e.g. "Ch. XX v. 1"
    public string? SourceVerse { get; set; }                     // optional verse reference
    public string RawSourceExcerpt { get; set; } = string.Empty; // verbatim original for audit

    // Full citation string kept for backwards compat with legacy `source` field.
    public string Source { get; set; } = string.Empty;

    // --- Semantic retrieval ---
    // 1536-dim from text-embedding-3-small, generated from title + content.
    public Vector? Embedding { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
