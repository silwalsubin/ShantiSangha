using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Services;

public interface ICurrentUser
{
    Task<User?> GetAsync();
}

/// <summary>
/// Resolves the current user by email from the JWT session.
/// ClerkId is stored for webhook integration but is not used
/// for user identity — email is the single source of truth.
/// </summary>
public class CurrentUserService : ICurrentUser
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly AppDbContext _db;
    private User? _cached;
    private bool _resolved;

    public CurrentUserService(IHttpContextAccessor httpContextAccessor, AppDbContext db)
    {
        _httpContextAccessor = httpContextAccessor;
        _db = db;
    }

    public async Task<User?> GetAsync()
    {
        if (_resolved) return _cached;
        _resolved = true;

        var email = _httpContextAccessor.HttpContext?.User.FindFirstValue("email");
        if (email is null) return null;

        var clerkId = _httpContextAccessor.HttpContext?.User.FindFirstValue("sub") ?? "";

        _cached = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (_cached is not null)
        {
            // Keep ClerkId in sync (may change on domain migration)
            if (_cached.ClerkId != clerkId && clerkId != "")
            {
                _cached.ClerkId = clerkId;
                _cached.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync();
            }
            return _cached;
        }

        // New user
        _cached = new User
        {
            Id = Guid.NewGuid(),
            ClerkId = clerkId,
            Email = email,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        _db.Users.Add(_cached);
        await _db.SaveChangesAsync();

        return _cached;
    }
}
