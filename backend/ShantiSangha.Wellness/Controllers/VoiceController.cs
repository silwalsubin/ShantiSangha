using Hangfire;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Shared.Interfaces;
using ShantiSangha.Wellness.Contracts;
using ShantiSangha.Wellness.Jobs;
using ShantiSangha.Wellness.Services;

namespace ShantiSangha.Wellness.Controllers;

[ApiController]
[Authorize]
[Route("api/voice")]
public class VoiceController(IVoiceService voiceService, ICurrentUser currentUser) : ControllerBase
{
    [HttpPost("upload-url")]
    public async Task<IActionResult> GetUploadUrl([FromBody] GetUploadUrlRequest request, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await voiceService.GetUploadUrlAsync(user.Id, request, ct);
        if (result is null)
            return BadRequest("Unsupported file type. Allowed: mp3, mp4, m4a, wav, webm, ogg");

        return Ok(result);
    }

    [HttpPost("entries")]
    public async Task<IActionResult> CreateEntry(
        [FromBody] CreateVoiceEntryRequest request,
        [FromServices] IBackgroundJobClient jobs,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        if (string.IsNullOrWhiteSpace(request.ObjectKey))
            return BadRequest("ObjectKey is required.");

        var result = await voiceService.CreateEntryAsync(user.Id, request, ct);

        jobs.Enqueue<TranscribeVoiceJob>(j => j.RunAsync(result.Id));

        return Created($"/voice/entries/{result.Id}", result);
    }

    [HttpGet("entries")]
    public async Task<IActionResult> ListEntries(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await voiceService.ListEntriesAsync(user.Id, page, pageSize, ct);
        return Ok(result);
    }

    [HttpGet("entries/{id:guid}")]
    public async Task<IActionResult> GetEntry(Guid id, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await voiceService.GetEntryAsync(user.Id, id, ct);
        if (result is null) return NotFound();

        return Ok(result);
    }

    [HttpPost("entries/{id:guid}/retry")]
    public async Task<IActionResult> RetryTranscription(
        Guid id,
        [FromServices] IBackgroundJobClient jobs,
        CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var entry = await voiceService.GetEntryAsync(user.Id, id, ct);
        if (entry is null) return NotFound();

        await voiceService.ResetStatusAsync(user.Id, id, ct);
        jobs.Enqueue<TranscribeVoiceJob>(j => j.RunAsync(id));

        return Ok(new { status = "Pending" });
    }

    [HttpDelete("entries/{id:guid}")]
    public async Task<IActionResult> DeleteEntry(Guid id, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var deleted = await voiceService.DeleteEntryAsync(user.Id, id, ct);
        return deleted ? NoContent() : NotFound();
    }
}
