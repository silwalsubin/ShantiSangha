using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.AgentFeedback.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.AgentFeedback.Controllers;

[ApiController]
[Authorize]
[Route("api/agent-feedback")]
public class AgentFeedbackController(
    IAgentFeedbackService service,
    ICurrentUser currentUser) : ControllerBase
{
    // Hardcoded dev gate. Only this account can read agent self-reports —
    // they capture cross-user content the LLM noticed and aren't meant
    // to be per-user-visible. Match the email check used elsewhere
    // (see /api/debug/* in Program.cs).
    private const string DevEmail = "silwalsubin@gmail.com";

    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] string? type = null,
        [FromQuery] string? severity = null,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();
        if (!string.Equals(user.Email, DevEmail, StringComparison.OrdinalIgnoreCase))
            return Forbid();

        try
        {
            var result = await service.ListAllAsync(type, severity, ct);
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }
}
