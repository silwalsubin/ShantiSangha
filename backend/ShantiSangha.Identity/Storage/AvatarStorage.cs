using Amazon;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Identity.Storage;

/// <summary>
/// S3 wrapper for user avatar images. Lives alongside the friends-media
/// bucket — avatars are user-shared identity content, same trust class as
/// friend chat media (visible to friends, not to the public). Keys follow
/// the pattern `avatars/{userId}/{guid}.{ext}` so we can find / clean up a
/// user's avatar history if needed without touching other prefixes.
/// </summary>
public class AvatarStorage : IDisposable
{
    private readonly AmazonS3Client _client;
    private readonly string _bucket;
    private readonly ILogger<AvatarStorage> _logger;

    public AvatarStorage(string bucket, string awsRegion, ILogger<AvatarStorage> logger)
    {
        _bucket = bucket;
        _logger = logger;
        _client = new AmazonS3Client(RegionEndpoint.GetBySystemName(awsRegion));
    }

    public string BuildKey(Guid userId, string contentType)
    {
        var ext = contentType.ToLowerInvariant() switch
        {
            "image/jpeg" or "image/jpg" => ".jpg",
            "image/png" => ".png",
            "image/heic" => ".heic",
            "image/webp" => ".webp",
            _ => ".bin"
        };
        return $"avatars/{userId}/{Guid.NewGuid()}{ext}";
    }

    public async Task<string> GetPresignedUploadUrlAsync(string objectKey, string contentType, TimeSpan expiry)
    {
        var request = new GetPreSignedUrlRequest
        {
            BucketName = _bucket,
            Key = objectKey,
            Verb = HttpVerb.PUT,
            Expires = DateTime.UtcNow.Add(expiry),
            ContentType = contentType
        };
        return await _client.GetPreSignedURLAsync(request);
    }

    public async Task<string> GetPresignedDownloadUrlAsync(string objectKey, TimeSpan expiry)
    {
        var request = new GetPreSignedUrlRequest
        {
            BucketName = _bucket,
            Key = objectKey,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(expiry)
        };
        return await _client.GetPreSignedURLAsync(request);
    }

    public async Task DeleteAsync(string objectKey)
    {
        try { await _client.DeleteObjectAsync(_bucket, objectKey); }
        catch (Exception ex) { _logger.LogWarning(ex, "Failed to delete avatar {Key}", objectKey); }
    }

    public void Dispose() => _client.Dispose();
}
