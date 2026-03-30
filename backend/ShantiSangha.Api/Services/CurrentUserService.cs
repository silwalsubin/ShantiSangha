using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Services;

public interface ICurrentUser
{
    Task<User?> GetAsync();
}

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

        _cached = await _db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (_cached is not null)
        {
            // Update email if we now have a real one and the stored one is missing/placeholder
            if (email is not null && (_cached.Email == "" || _cached.Email.EndsWith("@placeholder.local")))
            {
                _cached.Email = email;
                _cached.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync();
            }
            return _cached;
        }

        // Auto-create user on first API call (before Clerk webhook fires)
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
            // Duplicate email — user exists from a previous Clerk instance (e.g. domain change)
            // or race condition. Look up by email and update ClerkId to the new one.
            _db.Entry(_cached).State = EntityState.Detached;
            _cached = await _db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
            if (_cached is null && email is not null)
            {
                _cached = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
                if (_cached is not null)
                {
                    _cached.ClerkId = clerkId;
                    _cached.UpdatedAt = DateTime.UtcNow;
                    await _db.SaveChangesAsync();
                }
            }
        }
        return _cached;
    }
}
