namespace ShantiSangha.Wellness.Models;

/// <summary>
/// AI-generated portrait of who the user is — blending Vedic identity,
/// practice patterns, journal themes, and growth arc. Refreshes weekly
/// or when underlying data changes significantly.
/// </summary>
public class Portrait
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string Content { get; set; } = string.Empty;

    /// <summary>
    /// Hash of the input context used to generate this portrait.
    /// When context changes meaningfully, the hash changes and triggers regeneration.
    /// </summary>
    public string ContextHash { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; }
}
