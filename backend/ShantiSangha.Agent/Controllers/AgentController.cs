using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using ShantiSangha.Agent.AI;
using ShantiSangha.Agent.Contracts;

namespace ShantiSangha.Agent.Controllers;

[ApiController]
[Authorize]
[Route("api/agent")]
public class AgentController(AgentOrchestrator orchestrator, ILogger<AgentController> logger) : ControllerBase
{
    [HttpPost("chat")]
    public async Task Chat(
        [FromBody] AgentChatRequest body,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(body?.Message))
        {
            HttpContext.Response.StatusCode = 400;
            return;
        }

        HttpContext.Response.Headers.ContentType = "text/event-stream";
        HttpContext.Response.Headers.CacheControl = "no-cache";
        HttpContext.Response.Headers.Connection = "keep-alive";

        try
        {
            await foreach (var chunk in orchestrator.StreamAsync(body.Message, cancellationToken))
            {
                await WriteChunkAsync(chunk, cancellationToken);
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            await WriteChunkAsync(
                "\n\n(That took longer than expected. Please try again with a shorter request.)",
                cancellationToken);
        }
        catch (Exception ex) when (!cancellationToken.IsCancellationRequested)
        {
            // SSE headers have already been flushed by this point, so we can't
            // return a 500. Surface a clean line to the client so the typing
            // indicator resolves instead of hanging forever, and log details
            // server-side for diagnosis.
            logger.LogError(ex, "Agent chat failed mid-stream");
            await WriteChunkAsync(FriendlyMessageFor(ex), CancellationToken.None);
        }

        await HttpContext.Response.WriteAsync("data: [DONE]\n\n", Encoding.UTF8, CancellationToken.None);
        await HttpContext.Response.Body.FlushAsync(CancellationToken.None);
    }

    private async Task WriteChunkAsync(string text, CancellationToken ct)
    {
        var payload = JsonSerializer.Serialize(text);
        await HttpContext.Response.WriteAsync($"data: {payload}\n\n", Encoding.UTF8, ct);
        await HttpContext.Response.Body.FlushAsync(ct);
    }

    private static string FriendlyMessageFor(Exception ex)
    {
        var message = ex.Message ?? "";
        if (message.Contains("insufficient_quota", StringComparison.OrdinalIgnoreCase)
            || message.Contains("429", StringComparison.Ordinal))
        {
            return "I'm temporarily unavailable — the language model is out of capacity. Please try again later.";
        }
        return "Something went wrong. Please try again.";
    }
}
