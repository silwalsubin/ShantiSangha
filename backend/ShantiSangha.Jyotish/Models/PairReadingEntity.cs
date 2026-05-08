namespace ShantiSangha.Jyotish.Models;

/// <summary>
/// A viewer's private pre-composed reading of one specific subject's chart.
/// Asymmetric — A's row reading B is not the same content as B's row reading
/// A, since each is composed from the viewer's POV through their own chart.
/// Access requires an active BirthDetailShare grant from subject to viewer;
/// when the grant is revoked, this row is deleted and a fresh grant requires
/// a fresh generation.
/// </summary>
public class PairReadingEntity
{
    public Guid Id { get; set; }
    public Guid ViewerUserId { get; set; }
    public Guid SubjectUserId { get; set; }

    /// <summary>
    /// SHA-256 of the viewer's normalized birth details, the subject's
    /// normalized birth details, and the reading version constant. Any change
    /// to either chart or the composition logic invalidates this row.
    /// </summary>
    public string ChartHashPair { get; set; } = string.Empty;

    /// <summary>
    /// JSON object keyed by pair-section name (what_they_bring, where_it_eases,
    /// where_it_asks_work, the_shape). Values are composed prose strings.
    /// </summary>
    public string SectionsJson { get; set; } = "{}";

    /// <summary>
    /// JSON map of section → array of passage ids that informed it.
    /// </summary>
    public string PassageUsageJson { get; set; } = "{}";

    public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
