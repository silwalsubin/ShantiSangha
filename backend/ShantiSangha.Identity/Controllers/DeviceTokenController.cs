using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Identity.Contracts;
using ShantiSangha.Identity.Data;
using ShantiSangha.Identity.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Controllers;

[ApiController]
[Authorize]
[Route("api/me/device-token")]
public class DeviceTokenController(IdentityDbContext db, ICurrentUser currentUser) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Register([FromBody] RegisterDeviceTokenRequest request, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var existing = await db.DeviceTokens
            .FirstOrDefaultAsync(d => d.Token == request.Token, ct);

        if (existing is not null)
        {
            // Token exists — reassign to current user if needed, update timestamp
            existing.UserId = user.Id;
            existing.Platform = request.Platform;
            existing.UpdatedAt = DateTime.UtcNow;
        }
        else
        {
            // Remove stale tokens for this user + platform (e.g. after reinstall)
            var staleTokens = await db.DeviceTokens
                .Where(d => d.UserId == user.Id && d.Platform == request.Platform)
                .ToListAsync(ct);
            if (staleTokens.Count > 0)
                db.DeviceTokens.RemoveRange(staleTokens);

            db.DeviceTokens.Add(new DeviceToken
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                Token = request.Token,
                Platform = request.Platform,
                CreatedAt = DateTime.UtcNow,
                UpdatedAt = DateTime.UtcNow
            });
        }

        await db.SaveChangesAsync(ct);
        return Ok();
    }

    [HttpDelete]
    public async Task<IActionResult> Unregister([FromQuery] string token, CancellationToken ct)
    {
        var user = await currentUser.GetAsync();
        if (user is null) return Unauthorized();

        var existing = await db.DeviceTokens
            .FirstOrDefaultAsync(d => d.Token == token && d.UserId == user.Id, ct);

        if (existing is not null)
        {
            db.DeviceTokens.Remove(existing);
            await db.SaveChangesAsync(ct);
        }

        return NoContent();
    }
}
