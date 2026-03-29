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
            // Duplicate email — detach and retry lookup (race condition or shared empty email)
            _db.Entry(_cached).State = EntityState.Detached;
            _cached = await _db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        }
        return _cached;
    }
}
