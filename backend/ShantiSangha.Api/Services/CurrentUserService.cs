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
/// Resolves the current user from the JWT session.
/// Lookup order: ClerkId (sub claim) → email fallback (domain migration).
/// Email is kept in sync on every request.
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

        var clerkId = _httpContextAccessor.HttpContext?.User.FindFirstValue("sub");
        if (clerkId is null) return null;

        var email = _httpContextAccessor.HttpContext?.User.FindFirstValue("email");

        // Primary lookup: by ClerkId
        _cached = await _db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (_cached is not null)
        {
            if (email is not null && _cached.Email != email)
            {
                _cached.Email = email;
                _cached.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync();
            }
            return _cached;
        }

        // Fallback: by email (handles Clerk domain migration where ClerkId changes)
        if (email is not null)
        {
            _cached = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
            if (_cached is not null)
            {
                _cached.ClerkId = clerkId;
                _cached.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync();
                return _cached;
            }
        }

        // New user
        _cached = new User
        {
            Id = Guid.NewGuid(),
            ClerkId = clerkId,
            Email = email ?? $"{clerkId}@placeholder.local",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        _db.Users.Add(_cached);
        try
        {
            await _db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            _db.Entry(_cached).State = EntityState.Detached;
            _cached = await _db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        }
        return _cached;
    }
}
