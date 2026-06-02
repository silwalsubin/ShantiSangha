using Amazon;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Agent.Storage;

/// Stores photos the user attaches to the assistant. Unlike Friends media
/// (uploaded client-side via a presigned PUT), agent images arrive at the
/// server inline (base64 in the chat request), so we upload the bytes
/// directly with <see cref="UploadAsync"/> and hand back a presigned GET
/// on history load. Reuses the shared media bucket under an `agent/` prefix.
public class AgentMediaStorage : IDisposable
{
    private readonly AmazonS3Client _client;
    private readonly string _bucket;
    private readonly ILogger<AgentMediaStorage> _logger;

    public AgentMediaStorage(string bucket, string awsRegion, ILogger<AgentMediaStorage> logger)
    {
        _bucket = bucket;
        _logger = logger;
        _client = new AmazonS3Client(RegionEndpoint.GetBySystemName(awsRegion));
    }

    public async Task UploadAsync(string objectKey, byte[] data, string contentType, CancellationToken ct = default)
    {
        using var stream = new MemoryStream(data, writable: false);
        var request = new PutObjectRequest
        {
            BucketName = _bucket,
            Key = objectKey,
            InputStream = stream,
            ContentType = contentType
        };
        await _client.PutObjectAsync(request, ct);
    }

    public Task<string> GetPresignedDownloadUrlAsync(string objectKey, TimeSpan expiry)
    {
        var request = new GetPreSignedUrlRequest
        {
            BucketName = _bucket,
            Key = objectKey,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(expiry)
        };
        return _client.GetPreSignedURLAsync(request);
    }

    public void Dispose() => _client.Dispose();
}
