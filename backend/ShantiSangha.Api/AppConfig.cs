namespace ShantiSangha.Api;

public class AppConfig
{
    public required string DatabaseUrl { get; init; }
    public required string RedisUrl { get; init; }
    public required string ClerkAuthority { get; init; }
    public required string ClerkWebhookSecret { get; init; }
    public required string OpenAiApiKey { get; init; }
    public required string R2AccountId { get; init; }
    public required string R2AccessKeyId { get; init; }
    public required string R2SecretAccessKey { get; init; }
    public required string R2BucketName { get; init; }

    // Derived: Cloudflare R2 S3-compatible endpoint
    public string R2ServiceUrl => $"https://{R2AccountId}.r2.cloudflarestorage.com";

    public static AppConfig Load(IConfiguration config)
    {
        var db = config["DATABASE_URL"] ?? throw new InvalidOperationException("DATABASE_URL is required");
        var redis = config["REDIS_URL"] ?? throw new InvalidOperationException("REDIS_URL is required");
        var clerkAuthority = config["CLERK_AUTHORITY"] ?? throw new InvalidOperationException("CLERK_AUTHORITY is required");
        var clerkWebhookSecret = config["CLERK_WEBHOOK_SECRET"] ?? throw new InvalidOperationException("CLERK_WEBHOOK_SECRET is required");
        var openAiKey = config["OPENAI_API_KEY"] ?? throw new InvalidOperationException("OPENAI_API_KEY is required");
        var r2AccountId = config["R2_ACCOUNT_ID"] ?? throw new InvalidOperationException("R2_ACCOUNT_ID is required");
        var r2AccessKeyId = config["R2_ACCESS_KEY_ID"] ?? throw new InvalidOperationException("R2_ACCESS_KEY_ID is required");
        var r2SecretAccessKey = config["R2_SECRET_ACCESS_KEY"] ?? throw new InvalidOperationException("R2_SECRET_ACCESS_KEY is required");
        var r2BucketName = config["R2_BUCKET_NAME"] ?? throw new InvalidOperationException("R2_BUCKET_NAME is required");

        return new AppConfig
        {
            DatabaseUrl = db,
            RedisUrl = redis,
            ClerkAuthority = clerkAuthority,
            ClerkWebhookSecret = clerkWebhookSecret,
            OpenAiApiKey = openAiKey,
            R2AccountId = r2AccountId,
            R2AccessKeyId = r2AccessKeyId,
            R2SecretAccessKey = r2SecretAccessKey,
            R2BucketName = r2BucketName
        };
    }
}
