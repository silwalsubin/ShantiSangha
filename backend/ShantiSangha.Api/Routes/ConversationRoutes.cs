using System.Security.Claims;
using System.Text;
using Hangfire;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;
using ShantiSangha.Core.Services;
using ShantiSangha.Infrastructure.Data;
using ShantiSangha.Infrastructure.Jobs;

namespace ShantiSangha.Api.Routes;

public static class ConversationRoutes
{
    public static void MapConversationRoutes(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/conversations").RequireAuthorization();

        group.MapGet("/", ListConversations);
        group.MapPost("/", CreateConversation);
        group.MapGet("/{id:guid}", GetConversation);
        group.MapDelete("/{id:guid}", DeleteConversation);
        group.MapPost("/{id:guid}/messages", SendMessage);
    }

    private static async Task<IResult> ListConversations(
        ClaimsPrincipal principal, AppDbContext db)
    {
        var user = await RouteHelper.GetOrCreateUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        var conversations = await db.Conversations
            .Where(c => c.UserId == user.Id)
            .OrderByDescending(c => c.UpdatedAt)
            .Select(c => new
            {
                c.Id,
                c.Title,
                c.CreatedAt,
                c.UpdatedAt,
                LastMessage = db.Messages
                    .Where(m => m.ConversationId == c.Id)
                    .OrderByDescending(m => m.CreatedAt)
                    .Select(m => m.Content)
                    .FirstOrDefault()
            })
            .ToListAsync();

        return Results.Ok(conversations);
    }

    private static async Task<IResult> CreateConversation(
        ClaimsPrincipal principal, AppDbContext db)
    {
        var user = await RouteHelper.GetOrCreateUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        var conversation = new Conversation
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        db.Conversations.Add(conversation);
        await db.SaveChangesAsync();

        return Results.Created($"/conversations/{conversation.Id}", new { conversation.Id, conversation.CreatedAt });
    }

    private static async Task<IResult> GetConversation(
        Guid id, ClaimsPrincipal principal, AppDbContext db)
    {
        var user = await RouteHelper.GetOrCreateUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        var conversation = await db.Conversations
            .Where(c => c.Id == id && c.UserId == user.Id)
            .Select(c => new
            {
                c.Id,
                c.Title,
                c.CreatedAt,
                c.UpdatedAt,
                Messages = db.Messages
                    .Where(m => m.ConversationId == c.Id)
                    .OrderBy(m => m.CreatedAt)
                    .Select(m => new { m.Id, m.Role, m.Content, m.CreatedAt })
                    .ToList()
            })
            .FirstOrDefaultAsync();

        return conversation is null ? Results.NotFound() : Results.Ok(conversation);
    }

    private static async Task<IResult> DeleteConversation(
        Guid id, ClaimsPrincipal principal, AppDbContext db)
    {
        var user = await RouteHelper.GetOrCreateUserAsync(principal, db);
        if (user is null) return Results.Unauthorized();

        var conversation = await db.Conversations
            .FirstOrDefaultAsync(c => c.Id == id && c.UserId == user.Id);

        if (conversation is null) return Results.NotFound();

        db.Conversations.Remove(conversation);
        await db.SaveChangesAsync();

        return Results.NoContent();
    }

    private static async Task SendMessage(
        Guid id,
        ClaimsPrincipal principal,
        AppDbContext db,
        IChatService chatService,
        IBackgroundJobClient jobs,
        HttpContext httpContext,
        SendMessageRequest body,
        CancellationToken cancellationToken)
    {
        var user = await RouteHelper.GetOrCreateUserAsync(principal, db);
        if (user is null)
        {
            httpContext.Response.StatusCode = 401;
            return;
        }

        var conversation = await db.Conversations
            .FirstOrDefaultAsync(c => c.Id == id && c.UserId == user.Id, cancellationToken);

        if (conversation is null)
        {
            httpContext.Response.StatusCode = 404;
            return;
        }

        // SSE headers
        httpContext.Response.Headers.ContentType = "text/event-stream";
        httpContext.Response.Headers.CacheControl = "no-cache";
        httpContext.Response.Headers.Connection = "keep-alive";

        await foreach (var chunk in chatService.StreamResponseAsync(
            user.Id, id, body.Content, cancellationToken))
        {
            var line = $"data: {chunk}\n\n";
            await httpContext.Response.WriteAsync(line, Encoding.UTF8, cancellationToken);
            await httpContext.Response.Body.FlushAsync(cancellationToken);
        }

        await httpContext.Response.WriteAsync("data: [DONE]\n\n", Encoding.UTF8, cancellationToken);
        await httpContext.Response.Body.FlushAsync(cancellationToken);

        // Enqueue background jobs — generate embeddings for the two new messages,
        // then summarise and extract insights once there are enough messages
        var messageCount = await db.Messages.CountAsync(m => m.ConversationId == id, CancellationToken.None);

        var lastTwo = await db.Messages
            .Where(m => m.ConversationId == id)
            .OrderByDescending(m => m.CreatedAt)
            .Take(2)
            .Select(m => m.Id)
            .ToListAsync(CancellationToken.None);

        foreach (var msgId in lastTwo)
            jobs.Enqueue<GenerateEmbeddingJob>(j => j.RunForMessageAsync(msgId));

        // Generate summary every 10 messages
        if (messageCount % 10 == 0)
        {
            var userId = (await db.Users.FirstOrDefaultAsync(u => u.ClerkId == principal.FindFirst("sub")!.Value, CancellationToken.None))!.Id;
            var summaryJobId = jobs.Enqueue<GenerateSummaryJob>(j => j.RunForConversationAsync(id, userId));
            jobs.ContinueJobWith<ExtractInsightsJob>(summaryJobId, j =>
                j.RunAsync(id, ShantiSangha.Core.Models.SummarySourceType.Conversation, userId));
        }
    }
}

public record SendMessageRequest(string Content);
