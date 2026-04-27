using ShantiSangha.Friends.Contracts;

namespace ShantiSangha.Friends.Services;

public interface IFriendsService
{
    Task<List<FriendSummaryResponse>> ListFriendsAsync(Guid userId, CancellationToken ct = default);
    Task<FriendSummaryResponse?> GetFriendAsync(Guid userId, Guid friendshipId, CancellationToken ct = default);
    Task<CreateInvitationResponse> CreateInvitationAsync(Guid userId, string baseUrl, CancellationToken ct = default);
    Task<List<PendingInvitationResponse>> ListInvitationsAsync(Guid userId, string baseUrl, CancellationToken ct = default);
    Task<bool> RevokeInvitationAsync(Guid userId, Guid invitationId, CancellationToken ct = default);
    Task<InvitationPreviewResponse?> PreviewInvitationAsync(Guid userId, string token, CancellationToken ct = default);
    Task<FriendSummaryResponse> AcceptInvitationAsync(Guid userId, string token, CancellationToken ct = default);
    Task<bool> EndFriendshipAsync(Guid userId, Guid friendshipId, CancellationToken ct = default);
    Task<FriendSummaryResponse?> UpdateFriendAnnotationsAsync(
        Guid userId,
        Guid friendshipId,
        UpdateFriendAnnotationsRequest request,
        CancellationToken ct = default);
}

public class FriendsServiceException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
