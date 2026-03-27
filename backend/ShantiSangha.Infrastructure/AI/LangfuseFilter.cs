using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.SemanticKernel;
using Microsoft.Extensions.Logging;

namespace ShantiSangha.Infrastructure.AI;

/// <summary>
/// Semantic Kernel function invocation filter that logs every AI call to Langfuse.
/// Runs transparently around chat completions and embeddings.
/// If Langfuse is unavailable the call still succeeds — observability is best-effort.
/// </summary>
public class LangfuseFilter(
    IHttpClientFactory httpClientFactory,
    string publicKey,
    string secretKey,
    string baseUrl,
    ILogger<LangfuseFilter> logger) : IFunctionInvocationFilter
{
    public async Task OnFunctionInvocationAsync(FunctionInvocationContext context, Func<FunctionInvocationContext, Task> next)
    {
        var traceId = Guid.NewGuid().ToString();
        var generationId = Guid.NewGuid().ToString();
        var startTime = DateTime.UtcNow;

        // Run the actual AI call
        await next(context);

        var endTime = DateTime.UtcNow;
        var durationMs = (int)(endTime - startTime).TotalMilliseconds;

        // Fire-and-forget — never block the request for observability
        _ = Task.Run(async () =>
        {
            try
            {
                var input = context.Arguments.Count > 0
                    ? context.Arguments.First().Value?.ToString()
                    : null;

                var output = context.Result?.GetValue<object>()?.ToString();

                var payload = new
                {
                    batch = new[]
                    {
                        new
                        {
                            id = generationId,
                            type = "generation",
                            timestamp = startTime.ToString("O"),
                            body = new
                            {
                                traceId,
                                name = $"{context.Function.PluginName}.{context.Function.Name}",
                                startTime = startTime.ToString("O"),
                                endTime = endTime.ToString("O"),
                                input,
                                output,
                                metadata = new { durationMs }
                            }
                        }
                    }
                };

                var client = httpClientFactory.CreateClient();
                client.DefaultRequestHeaders.Authorization =
                    new System.Net.Http.Headers.AuthenticationHeaderValue(
                        "Basic",
                        Convert.ToBase64String(
                            System.Text.Encoding.UTF8.GetBytes($"{publicKey}:{secretKey}")));

                await client.PostAsJsonAsync($"{baseUrl}/api/public/ingestion", payload);
            }
            catch (Exception ex)
            {
                logger.LogDebug(ex, "Langfuse trace failed — continuing without observability");
            }
        });
    }
}
