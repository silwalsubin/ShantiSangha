namespace ShantiSangha.Api;

public class AppConfig
{
    public required string DatabaseUrl { get; init; }
    public required string RedisUrl { get; init; }
    public required string FirebaseProjectId { get; init; }
    public required string OpenAiApiKey { get; init; }
    public required string VoiceBucketName { get; init; }

    /// <summary>S3 bucket where friend chat media (images, voice messages) is
    /// stored. Kept separate from VoiceBucketName so retention, IAM, and
    /// lifecycle policies can evolve independently — voice notes are solo
    /// content for the owning user only, while friends media is shared
    /// between two users and hard-deleted when a friendship ends.</summary>
    public required string FriendsMediaBucketName { get; init; }

    // Optional — Langfuse AI observability (app starts without these)
    public string? LangfusePublicKey { get; init; }
    public string? LangfuseSecretKey { get; init; }
    public string LangfuseBaseUrl { get; init; } = "https://cloud.langfuse.com";

    // When true, unhandled exceptions return full details in API responses
    public bool ExposeErrors { get; init; }

    public bool LangfuseEnabled =>
        !string.IsNullOrEmpty(LangfusePublicKey) && !string.IsNullOrEmpty(LangfuseSecretKey);

    public static AppConfig Load(IConfiguration config)
    {
        var db = config["DATABASE_URL"] ?? throw new InvalidOperationException("DATABASE_URL is required");
        var redis = config["REDIS_URL"] ?? throw new InvalidOperationException("REDIS_URL is required");
        var firebaseProjectId = config["FIREBASE_PROJECT_ID"] ?? throw new InvalidOperationException("FIREBASE_PROJECT_ID is required");
        var openAiKey = config["OPENAI_API_KEY"] ?? throw new InvalidOperationException("OPENAI_API_KEY is required");
        var voiceBucket = config["VOICE_BUCKET_NAME"] ?? throw new InvalidOperationException("VOICE_BUCKET_NAME is required");
        // Prefer the dedicated friends-media bucket, but fall back to the
        // voice bucket so the backend can boot before the Terraform that
        // provisions the new bucket has been applied. Keys live under a
        // `friends/{friendshipId}/...` prefix either way, so they don't
        // collide with solo voice notes — but media uploaded during the
        // fallback window won't be reachable after the env var flips, since
        // presigned URLs are bound to the configured bucket. Apply the
        // Terraform soon and the fallback path goes dormant.
        var friendsMediaBucket = config["FRIENDS_MEDIA_BUCKET_NAME"];
        if (string.IsNullOrWhiteSpace(friendsMediaBucket))
        {
            Serilog.Log.Warning(
                "FRIENDS_MEDIA_BUCKET_NAME is not set — falling back to VOICE_BUCKET_NAME ({Bucket}). " +
                "Apply infrastructure/terraform to provision the dedicated friends-media bucket and remove this fallback.",
                voiceBucket);
            friendsMediaBucket = voiceBucket;
        }

        return new AppConfig
        {
            DatabaseUrl = db,
            RedisUrl = redis,
            FirebaseProjectId = firebaseProjectId,
            OpenAiApiKey = openAiKey,
            VoiceBucketName = voiceBucket,
            FriendsMediaBucketName = friendsMediaBucket,
            LangfusePublicKey = config["LANGFUSE_PUBLIC_KEY"],
            LangfuseSecretKey = config["LANGFUSE_SECRET_KEY"],
            LangfuseBaseUrl = config["LANGFUSE_BASE_URL"] ?? "https://cloud.langfuse.com",
            ExposeErrors = string.Equals(config["EXPOSE_ERRORS"], "true", StringComparison.OrdinalIgnoreCase)
        };
    }
}
