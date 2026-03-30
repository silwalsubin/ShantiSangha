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
        var email = _httpContextAccessor.HttpContext?.User.FindFirstValue("email");

        if (clerkId is null || email is null) return null;

        // Look up by ClerkId first
        _cached = await _db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (_cached is not null)
        {
            if (_cached.Email != email)
            {
                _cached.Email = email;
                _cached.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync();
            }
            return _cached;
        }

        // ClerkId not found — check if email exists (user from a previous Clerk instance)
        _cached = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (_cached is not null)
        {
            _cached.ClerkId = clerkId;
            _cached.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync();
            return _cached;
        }

        // New user — create
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
