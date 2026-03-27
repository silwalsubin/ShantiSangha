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

        _cached = await _db.Users.FirstOrDefaultAsync(u => u.ClerkId == clerkId);
        if (_cached is not null) return _cached;

        // Auto-create user on first API call (before Clerk webhook fires)
        _cached = new User
        {
            Id = Guid.NewGuid(),
            ClerkId = clerkId,
            Email = _httpContextAccessor.HttpContext?.User.FindFirstValue("email") ?? "",
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        _db.Users.Add(_cached);
        await _db.SaveChangesAsync();
        return _cached;
    }
}
