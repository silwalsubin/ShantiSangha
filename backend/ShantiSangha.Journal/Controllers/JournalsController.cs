using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Journal.Contracts;
using ShantiSangha.Journal.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Journal.Controllers;

[ApiController]
[Authorize]
[Route("api/journals")]
public class JournalsController(IJournalService journalService, ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> List(
        int page = 1, int pageSize = 20, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var journals = await journalService.ListAsync(user.Id, page, pageSize, ct);
        return Ok(journals);
    }

    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateJournalRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await journalService.CreateAsync(user.Id, body, ct);
        return Created($"/journals/{result.Id}", result);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetById(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var journal = await journalService.GetByIdAsync(id, user.Id, ct);
        return journal is null ? NotFound() : Ok(journal);
    }

    [HttpPatch("{id:guid}")]
    public async Task<IActionResult> Update(
        Guid id, [FromBody] UpdateJournalRequest body, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var found = await journalService.UpdateAsync(id, user.Id, body, ct);
        return found ? NoContent() : NotFound();
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct = default)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var found = await journalService.DeleteAsync(id, user.Id, ct);
        return found ? NoContent() : NotFound();
    }
}
