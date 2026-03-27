using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Routes;

public static class WebhookRoutes
{
    public static void MapWebhookRoutes(this WebApplication app)
    {
        app.MapPost("/webhooks/clerk", HandleClerkWebhook)
            .AllowAnonymous();
    }

    private static async Task<IResult> HandleClerkWebhook(
        HttpRequest request,
        AppConfig config,
        AppDbContext db,
        ILogger<Program> logger)
    {
        // Verify Svix signature from Clerk
        if (!await VerifySignature(request, config.ClerkWebhookSecret))
        {
            logger.LogWarning("Clerk webhook signature verification failed");
            return Results.Unauthorized();
        }

        request.Body.Position = 0;
        using var doc = await JsonDocument.ParseAsync(request.Body);
        var root = doc.RootElement;

        var eventType = root.GetProperty("type").GetString();
        var data = root.GetProperty("data");

        switch (eventType)
        {
            case "user.created":
                await SyncUser(data, db, logger);
                break;
            case "user.updated":
                await UpdateUser(data, db, logger);
                break;
            case "user.deleted":
                logger.LogInformation("User deleted event received for {ClerkId}", data.GetProperty("id").GetString());
                break;
            default:
                logger.LogDebug("Unhandled Clerk webhook event: {EventType}", eventType);
                break;
        }

        return Results.Ok();
    }

    private static async Task SyncUser(JsonElement data, AppDbContext db, ILogger logger)
    {
        var clerkId = data.GetProperty("id").GetString()!;
        var email = data.GetProperty("email_addresses")[0].GetProperty("email_address").GetString()!;

        var exists = await db.Users.AnyAsync(u => u.ClerkId == clerkId);
        if (exists) return;

        var user = new User
        {
            Id = Guid.NewGuid(),
            ClerkId = clerkId,
            Email = email,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        var profile = new Profile
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            OnboardingCompleted = false,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.Users.Add(user);
        db.Profiles.Add(profile);
        await db.SaveChangesAsync();

        logger.LogInformation("Synced new user {ClerkId}", clerkId);
    }

    private static async Task UpdateUser(JsonElement data, AppDbContext db, ILogger logger)
    {
        var clerkId = data.GetProperty("id").GetString()!;
        var email = data.GetProperty("email_addresses")[0].GetProperty("email_address").GetString()!;

        var user = await db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (user is null) return;

        user.Email = email;
        user.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();

        logger.LogInformation("Updated user {ClerkId}", clerkId);
    }

    private static async Task<bool> VerifySignature(HttpRequest request, string secret)
    {
        request.EnableBuffering();

        if (!request.Headers.TryGetValue("svix-id", out var svixId) ||
            !request.Headers.TryGetValue("svix-timestamp", out var svixTimestamp) ||
            !request.Headers.TryGetValue("svix-signature", out var svixSignature))
            return false;

        var body = await new StreamReader(request.Body, leaveOpen: true).ReadToEndAsync();
        request.Body.Position = 0;

        var signedContent = $"{svixId}.{svixTimestamp}.{body}";
        var secretBytes = Convert.FromBase64String(secret.Replace("whsec_", ""));
        var hash = HMACSHA256.HashData(secretBytes, Encoding.UTF8.GetBytes(signedContent));
        var computed = $"v1,{Convert.ToBase64String(hash)}";

        return svixSignature.ToString().Split(' ').Any(s => s == computed);
    }
}
