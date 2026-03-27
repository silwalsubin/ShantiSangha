namespace ShantiSangha.Api;

public class AppConfig
{
    public required string DatabaseUrl { get; init; }
    public required string RedisUrl { get; init; }
    public required string ClerkAuthority { get; init; }
    public required string ClerkWebhookSecret { get; init; }
    public required string OpenAiApiKey { get; init; }

    public static AppConfig Load(IConfiguration config)
    {
        var db = config["DATABASE_URL"] ?? throw new InvalidOperationException("DATABASE_URL is required");
        var redis = config["REDIS_URL"] ?? throw new InvalidOperationException("REDIS_URL is required");
        var clerkAuthority = config["CLERK_AUTHORITY"] ?? throw new InvalidOperationException("CLERK_AUTHORITY is required");
        var clerkWebhookSecret = config["CLERK_WEBHOOK_SECRET"] ?? throw new InvalidOperationException("CLERK_WEBHOOK_SECRET is required");
        var openAiKey = config["OPENAI_API_KEY"] ?? throw new InvalidOperationException("OPENAI_API_KEY is required");

        return new AppConfig
        {
            DatabaseUrl = db,
            RedisUrl = redis,
            ClerkAuthority = clerkAuthority,
            ClerkWebhookSecret = clerkWebhookSecret,
            OpenAiApiKey = openAiKey
        };
    }
}
