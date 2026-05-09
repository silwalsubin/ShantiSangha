using ShantiSangha.Friends.Contracts;

namespace ShantiSangha.Friends.Services;

/// Owns the Person + Connection table reads and writes. The existing
/// `IFriendsService` keeps owning conversation/messaging concerns;
/// this service owns the Circle data model layered on top.
public interface IConnectionsService
{
    Task<List<ConnectionResponse>> ListAsync(Guid userId, CancellationToken ct = default);

    Task<ConnectionResponse?> GetAsync(Guid userId, Guid connectionId, CancellationToken ct = default);

    /// Creates a new local Person + Connection in one transaction.
    /// `req.Circles` is a free-form tag set; null/empty is allowed.
    Task<ConnectionResponse> CreateLocalAsync(
        Guid userId,
        CreateConnectionRequest req,
        CancellationToken ct = default);

    /// Updates Connection-overlay fields. Returns null when the row
    /// isn't owned by `userId` (controller maps to 404).
    Task<ConnectionResponse?> UpdateAsync(
        Guid userId,
        Guid connectionId,
        UpdateConnectionRequest req,
        CancellationToken ct = default);

    /// Updates Person fields. Returns null when not found; throws
    /// `FriendsServiceException("forbidden", ...)` when the caller
    /// can't edit (linked Person belonging to someone else).
    Task<PersonResponse?> UpdatePersonAsync(
        Guid userId,
        Guid connectionId,
        UpdatePersonRequest req,
        CancellationToken ct = default);

    /// Removes the Connection. For paired rows, also ends the
    /// underlying friendship (which removes the other side's
    /// Connection too via the same path).
    Task<bool> DeleteAsync(Guid userId, Guid connectionId, CancellationToken ct = default);

    /// Append a new "important date" to the Connection. Returns null
    /// when the connection isn't owned by `userId`.
    Task<ConnectionDateResponse?> AddDateAsync(
        Guid userId,
        Guid connectionId,
        AddConnectionDateRequest req,
        CancellationToken ct = default);

    /// Replace label/date on an existing entry. Returns null when the
    /// row doesn't exist or isn't owned by `userId`.
    Task<ConnectionDateResponse?> UpdateDateAsync(
        Guid userId,
        Guid connectionId,
        Guid dateId,
        UpdateConnectionDateRequest req,
        CancellationToken ct = default);

    /// Drop a single entry. False when not found / not owned.
    Task<bool> DeleteDateAsync(
        Guid userId,
        Guid connectionId,
        Guid dateId,
        CancellationToken ct = default);
}
