using Amazon;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Wellness.Storage;

public class StorageService : IDisposable
{
    private readonly AmazonS3Client _client;
    private readonly string _bucket;
    private readonly ILogger<StorageService> _logger;

    public StorageService(string bucket, string awsRegion, ILogger<StorageService> logger)
    {
        _bucket = bucket;
        _logger = logger;
        // On ECS Fargate the task role credentials are picked up automatically.
        // Locally, the default credential chain (env vars / ~/.aws) is used.
        _client = new AmazonS3Client(RegionEndpoint.GetBySystemName(awsRegion));
    }

    /// <summary>Generate a presigned PUT URL the client uploads to directly.</summary>
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

        var url = await _client.GetPreSignedURLAsync(request);
        _logger.LogDebug("Generated presigned upload URL for {Key}", objectKey);
        return url;
    }

    /// <summary>Download an object into a stream for processing (e.g. transcription).</summary>
    public async Task<Stream> DownloadAsync(string objectKey)
    {
        var response = await _client.GetObjectAsync(_bucket, objectKey);
        return response.ResponseStream;
    }

    /// <summary>Delete an object (e.g. after transcription to save storage costs).</summary>
    public async Task DeleteAsync(string objectKey)
    {
        await _client.DeleteObjectAsync(_bucket, objectKey);
        _logger.LogDebug("Deleted object {Key}", objectKey);
    }

    public void Dispose() => _client.Dispose();
}
