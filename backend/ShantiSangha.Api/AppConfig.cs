namespace ShantiSangha.Api;

public class AppConfig
{
    public required string DatabaseUrl { get; init; }
    public required string RedisUrl { get; init; }
    public required string ClerkAuthority { get; init; }
    public required string ClerkWebhookSecret { get; init; }
    public required string OpenAiApiKey { get; init; }
    public required string VoiceBucketName { get; init; }

    // Optional — Langfuse AI observability (app starts without these)
    public string? LangfusePublicKey { get; init; }
    public string? LangfuseSecretKey { get; init; }
    public string LangfuseBaseUrl { get; init; } = "https://cloud.langfuse.com";

    public bool LangfuseEnabled =>
        !string.IsNullOrEmpty(LangfusePublicKey) && !string.IsNullOrEmpty(LangfuseSecretKey);

    public static AppConfig Load(IConfiguration config)
    {
        var db = config["DATABASE_URL"] ?? throw new InvalidOperationException("DATABASE_URL is required");
        var redis = config["REDIS_URL"] ?? throw new InvalidOperationException("REDIS_URL is required");
        var clerkAuthority = config["CLERK_AUTHORITY"] ?? throw new InvalidOperationException("CLERK_AUTHORITY is required");
        var clerkWebhookSecret = config["CLERK_WEBHOOK_SECRET"] ?? throw new InvalidOperationException("CLERK_WEBHOOK_SECRET is required");
        var openAiKey = config["OPENAI_API_KEY"] ?? throw new InvalidOperationException("OPENAI_API_KEY is required");
        var voiceBucket = config["VOICE_BUCKET_NAME"] ?? throw new InvalidOperationException("VOICE_BUCKET_NAME is required");

        return new AppConfig
        {
            DatabaseUrl = db,
            RedisUrl = redis,
            ClerkAuthority = clerkAuthority,
            ClerkWebhookSecret = clerkWebhookSecret,
            OpenAiApiKey = openAiKey,
            VoiceBucketName = voiceBucket,
            LangfusePublicKey = config["LANGFUSE_PUBLIC_KEY"],
            LangfuseSecretKey = config["LANGFUSE_SECRET_KEY"],
            LangfuseBaseUrl = config["LANGFUSE_BASE_URL"] ?? "https://cloud.langfuse.com"
        };
    }
}
