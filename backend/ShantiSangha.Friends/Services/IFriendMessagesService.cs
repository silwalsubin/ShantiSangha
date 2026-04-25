using ShantiSangha.Friends.Contracts;

namespace ShantiSangha.Friends.Services;

public interface IFriendMessagesService
{
    Task<List<FriendMessageResponse>?> ListMessagesAsync(
        Guid userId, Guid friendshipId, DateTime? before, int limit, CancellationToken ct = default);

    Task<FriendMessageResponse?> SendTextAsync(
        Guid userId, Guid friendshipId, string body, CancellationToken ct = default);

    Task<CreateMediaUploadResponse?> CreateImageUploadAsync(
        Guid userId, Guid friendshipId, string contentType, CancellationToken ct = default);

    Task<CreateMediaUploadResponse?> CreateVoiceUploadAsync(
        Guid userId, Guid friendshipId, string contentType, CancellationToken ct = default);

    Task<FriendMessageResponse?> CommitImageMessageAsync(
        Guid userId, Guid friendshipId, CommitMediaMessageRequest req, CancellationToken ct = default);

    Task<FriendMessageResponse?> CommitVoiceMessageAsync(
        Guid userId, Guid friendshipId, CommitMediaMessageRequest req, CancellationToken ct = default);

    Task<bool> MarkReadAsync(
        Guid userId, Guid friendshipId, Guid messageId, CancellationToken ct = default);
}
