using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Routes;

public static class RouteHelper
{
    /// <summary>
    /// Gets or creates a user from the ClaimsPrincipal's sub claim.
    /// Auto-creates the user record on first API call if the Clerk webhook hasn't fired yet.
    /// </summary>
    public static async Task<User?> GetOrCreateUserAsync(ClaimsPrincipal principal, AppDbContext db)
    {
        var clerkId = principal.FindFirstValue("sub");
        if (clerkId is null) return null;

        var user = await db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (user is not null) return user;

        // Auto-create user on first API call
        user = new User
        {
            Id = Guid.NewGuid(),
            ClerkId = clerkId,
            Email = principal.FindFirstValue("email") ?? "",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        db.Users.Add(user);
        await db.SaveChangesAsync();
        return user;
    }
}
