using System.Net.WebSockets;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Friends.Realtime;

/// <summary>
/// HTTP endpoint that upgrades to a WebSocket and routes incoming
/// frames into the realtime hub. URL:
///
///   wss://shantisangha.com/api/chat/realtime?token=&lt;jwt&gt;&amp;conversationId=&lt;id&gt;
///
/// The token in the query string is consumed by the JwtBearer
/// `OnMessageReceived` hook in Program.cs (the WebSocket upgrade
/// handshake doesn't let clients set arbitrary headers, so the URL is
/// the standard place to put it). After auth runs, this handler reads
/// the user via the normal `ICurrentUser` path.
/// </summary>
public static class ChatWebSocketEndpoint
{
    public static void MapChatRealtime(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/chat/realtime", HandleAsync).RequireAuthorization();
    }

    private static async Task HandleAsync(
        HttpContext context,
        ICurrentUser currentUser,
        IConversationMembershipService membership,
        IChatRealtimeHub hub,
        ILogger<InMemoryChatRealtimeHub> logger)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("WebSocket upgrade required.");
            return;
        }

        var user = await currentUser.GetAsync();
        if (user is null)
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        var conversationIdRaw = context.Request.Query["conversationId"].ToString();
        if (!Guid.TryParse(conversationIdRaw, out var conversationId))
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("conversationId required.");
            return;
        }

        // Membership goes through the cross-module abstraction so a
        // future Groups module plugs in without touching this endpoint.
        if (!await membership.IsMemberAsync(conversationId, user.Id, context.RequestAborted))
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return;
        }

        var socket = await context.WebSockets.AcceptWebSocketAsync();
        hub.Register(user.Id, conversationId, socket);
        logger.LogInformation(
            "realtime.connected user={UserId} conversation={ConversationId}",
            user.Id, conversationId);

        try
        {
            await ReadLoopAsync(socket, user.Id, conversationId, hub, logger, context.RequestAborted);
        }
        finally
        {
            hub.Unregister(socket);
            if (socket.State == WebSocketState.Open || socket.State == WebSocketState.CloseReceived)
            {
                try
                {
                    await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None);
                }
                catch { /* swallow */ }
            }
        }
    }

    private static async Task ReadLoopAsync(
        WebSocket socket,
        Guid userId,
        Guid conversationId,
        IChatRealtimeHub hub,
        ILogger logger,
        CancellationToken ct)
    {
        var buffer = new byte[4096];
        while (socket.State == WebSocketState.Open && !ct.IsCancellationRequested)
        {
            WebSocketReceiveResult result;
            try
            {
                result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), ct);
            }
            catch (WebSocketException) { return; }
            catch (OperationCanceledException) { return; }

            if (result.MessageType == WebSocketMessageType.Close) return;
            if (result.MessageType != WebSocketMessageType.Text || result.Count == 0) continue;

            // Only `typing` is accepted from the client. State-changing
            // actions (send/edit/delete/mark-read) go through REST so
            // failures are visible via HTTP status codes.
            try
            {
                using var doc = JsonDocument.Parse(buffer.AsMemory(0, result.Count));
                if (!doc.RootElement.TryGetProperty("kind", out var kindEl)) continue;
                var kind = kindEl.GetString();

                if (kind == "typing")
                {
                    var isTyping = doc.RootElement.TryGetProperty("isTyping", out var typingEl)
                        && typingEl.ValueKind == JsonValueKind.True;

                    await hub.PublishAsync(conversationId, "typing", new
                    {
                        conversationId,
                        fromUserId = userId,
                        isTyping
                    }, ct);
                }
                // Other inbound kinds are silently ignored.
            }
            catch (JsonException)
            {
                logger.LogDebug("realtime.read non-JSON frame from user={UserId}", userId);
            }
        }
    }
}
