using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Core.Models;
using ShantiSangha.Infrastructure.Data;

namespace ShantiSangha.Api.Services;

public interface ICurrentUser
{
    Task<User?> GetAsync();
}

/// <summary>
/// Resolves the current user by email from the Firebase JWT.
/// Firebase tokens include email and user_id (sub) claims.
/// </summary>
public class CurrentUserService : ICurrentUser
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly AppDbContext _db;
    private readonly ILogger<CurrentUserService> _logger;
    private User? _cached;
    private bool _resolved;

    public CurrentUserService(IHttpContextAccessor httpContextAccessor, AppDbContext db, ILogger<CurrentUserService> logger)
    {
        _httpContextAccessor = httpContextAccessor;
        _db = db;
        _logger = logger;
    }

    public async Task<User?> GetAsync()
    {
        if (_resolved) return _cached;
        _resolved = true;

        var email = _httpContextAccessor.HttpContext?.User.FindFirstValue("email");
        var firebaseUid = _httpContextAccessor.HttpContext?.User.FindFirstValue("user_id")
                       ?? _httpContextAccessor.HttpContext?.User.FindFirstValue("sub")
                       ?? "";

        if (!IsValidEmail(email))
        {
            _logger.LogWarning("Invalid or missing email in JWT. sub={Uid}, email={Email}", firebaseUid, email ?? "(null)");
            return null;
        }

        // Look up by email
        _cached = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (_cached is not null)
        {
            // Keep auth provider ID in sync
            if (_cached.ClerkId != firebaseUid && firebaseUid != "")
            {
                _cached.ClerkId = firebaseUid;
                _cached.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync();
            }
            return _cached;
        }

        // New user
        _cached = new User
        {
            Id = Guid.NewGuid(),
            ClerkId = firebaseUid,
            Email = email!,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        _db.Users.Add(_cached);
        await _db.SaveChangesAsync();

        return _cached;
    }

    private static bool IsValidEmail(string? email)
    {
        if (string.IsNullOrWhiteSpace(email)) return false;
        if (!email.Contains('@')) return false;
        if (email.Contains(' ')) return false;
        return true;
    }
}
