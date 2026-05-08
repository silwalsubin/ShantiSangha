namespace ShantiSangha.Shared.Interfaces;

/// <summary>
/// Manages directional grants where one user opts to share their birth
/// details with another for the purpose of generating the grantee's
/// private Vedic chart reading. Implementation lives in the Friends
/// module; the interface is in Shared so cross-module gating (Jyotish
/// chart-reading endpoints, future chat surfaces) can call through
/// without taking a hard reference on Friends.
/// </summary>
public interface IBirthDetailShareService
{
    /// <summary>
    /// Grants the grantee read access to the grantor's chart data. Idempotent;
    /// re-granting an existing share returns false (already granted) without
    /// touching the row. Both parties must already be friends.
    /// </summary>
    Task<bool> GrantAsync(Guid grantorUserId, Guid granteeUserId, CancellationToken ct = default);

    /// <summary>
    /// Revokes a previously granted share. Returns true if a row was deleted.
    /// Callers should also invalidate any pair reading + chat the grantee
    /// generated using this access.
    /// </summary>
    Task<bool> RevokeAsync(Guid grantorUserId, Guid granteeUserId, CancellationToken ct = default);

    /// <summary>
    /// Checks if the viewer has been granted access to the subject's chart.
    /// </summary>
    Task<bool> HasAccessAsync(Guid viewerUserId, Guid subjectUserId, CancellationToken ct = default);

    /// <summary>
    /// User IDs the current user has shared their details with.
    /// </summary>
    Task<IReadOnlyList<Guid>> ListGrantedToAsync(Guid grantorUserId, CancellationToken ct = default);

    /// <summary>
    /// User IDs that have shared their details with the current user.
    /// </summary>
    Task<IReadOnlyList<Guid>> ListReceivedFromAsync(Guid granteeUserId, CancellationToken ct = default);
}
