using ShantiSangha.Friends.Contracts;

namespace ShantiSangha.Friends.Services;

/// Owner-private keepsakes attached to a Connection. Two-step upload
/// (presigned PUT → commit) mirrors the friend-message media path so
/// large bytes never stream through ECS. The `Connection` cascade
/// covers row deletion; this service additionally sweeps S3.
public interface IConnectionAttachmentsService
{
    Task<List<ConnectionAttachmentResponse>?> ListAsync(
        Guid userId,
        Guid connectionId,
        CancellationToken ct = default);

    Task<CreateConnectionAttachmentUploadResponse?> CreateUploadUrlAsync(
        Guid userId,
        Guid connectionId,
        CreateConnectionAttachmentUploadRequest req,
        CancellationToken ct = default);

    Task<ConnectionAttachmentResponse?> CommitAsync(
        Guid userId,
        Guid connectionId,
        CommitConnectionAttachmentRequest req,
        CancellationToken ct = default);

    Task<ConnectionAttachmentResponse?> UpdateAsync(
        Guid userId,
        Guid connectionId,
        Guid attachmentId,
        UpdateConnectionAttachmentRequest req,
        CancellationToken ct = default);

    Task<bool> DeleteAsync(
        Guid userId,
        Guid connectionId,
        Guid attachmentId,
        CancellationToken ct = default);

    /// Called by `ConnectionsService.DeleteAsync` so the S3 objects don't
    /// outlive the rows. Ignores the return value of bulk delete — the
    /// row-level CASCADE has already happened in the same transaction.
    Task PurgeForConnectionAsync(Guid connectionId, CancellationToken ct = default);
}
