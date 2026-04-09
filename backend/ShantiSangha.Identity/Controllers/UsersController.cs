using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ShantiSangha.Identity.Contracts;
using ShantiSangha.Identity.Services;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Controllers;

[ApiController]
[Authorize]
[Route("api/me")]
public class UsersController(IUserService userService, ICurrentUser currentUser) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetMe(CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var result = await userService.GetMeAsync(user.Id, ct);
        if (result is null) return Unauthorized();

        return Ok(result);
    }

    [HttpPatch]
    public async Task<IActionResult> UpdateMe([FromBody] UpdateMeRequest request, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var success = await userService.UpdateMeAsync(user.Id, request, ct);
        if (!success) return Problem("Profile not found");

        return NoContent();
    }
}
