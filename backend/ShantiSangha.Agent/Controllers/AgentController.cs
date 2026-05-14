using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Agent.AI;
using ShantiSangha.Agent.Contracts;

namespace ShantiSangha.Agent.Controllers;

[ApiController]
[Authorize]
[Route("api/agent")]
public class AgentController(AgentOrchestrator orchestrator) : ControllerBase
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
                var payload = JsonSerializer.Serialize(chunk);
                await HttpContext.Response.WriteAsync($"data: {payload}\n\n", Encoding.UTF8, cancellationToken);
                await HttpContext.Response.Body.FlushAsync(cancellationToken);
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            var timeoutPayload = JsonSerializer.Serialize("\n\n(Agent loop timed out. Please try again with a shorter request.)");
            await HttpContext.Response.WriteAsync($"data: {timeoutPayload}\n\n", Encoding.UTF8, cancellationToken);
        }

        await HttpContext.Response.WriteAsync("data: [DONE]\n\n", Encoding.UTF8, cancellationToken);
        await HttpContext.Response.Body.FlushAsync(cancellationToken);
    }
}
