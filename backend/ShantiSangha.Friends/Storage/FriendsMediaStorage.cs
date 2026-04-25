using Amazon;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Friends.Storage;

public class FriendsMediaStorage : IDisposable
{
    private readonly AmazonS3Client _client;
    private readonly string _bucket;
    private readonly ILogger<FriendsMediaStorage> _logger;

    public FriendsMediaStorage(string bucket, string awsRegion, ILogger<FriendsMediaStorage> logger)
    {
        _bucket = bucket;
        _logger = logger;
        _client = new AmazonS3Client(RegionEndpoint.GetBySystemName(awsRegion));
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
        await _client.DeleteObjectAsync(_bucket, objectKey);
    }

    public async Task DeleteManyAsync(IEnumerable<string> objectKeys)
    {
        var keys = objectKeys.Where(k => !string.IsNullOrWhiteSpace(k)).ToList();
        if (keys.Count == 0) return;

        var request = new DeleteObjectsRequest
        {
            BucketName = _bucket,
            Objects = keys.Select(k => new KeyVersion { Key = k }).ToList()
        };
        try
        {
            await _client.DeleteObjectsAsync(request);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Bulk delete partially failed for {Count} keys", keys.Count);
        }
    }

    public void Dispose() => _client.Dispose();
}
