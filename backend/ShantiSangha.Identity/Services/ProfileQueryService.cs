using Microsoft.EntityFrameworkCore;
using ShantiSangha.Identity.Data;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Services;

public class ProfileQueryService(IdentityDbContext db) : IProfileQueryService
{
    public async Task<string?> GetDisplayNameAsync(Guid userId, CancellationToken ct = default)
    {
        return await db.Profiles
            .Where(p => p.UserId == userId)
            .Select(p => p.DisplayName)
            .FirstOrDefaultAsync(ct);
    }
}
