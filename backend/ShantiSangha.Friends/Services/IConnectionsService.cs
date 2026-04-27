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
    /// `req.RelationType` must parse to `ConnectionType`; `Other`
    /// requires `CustomRelationLabel`.
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
}
