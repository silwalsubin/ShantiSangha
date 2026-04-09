using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ShantiSangha.Identity.Data;
using ShantiSangha.Identity.Models;
using ShantiSangha.Shared.Interfaces;

namespace ShantiSangha.Identity.Services;

public class CurrentUserService : ICurrentUser
{
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly IdentityDbContext _db;
    private readonly ILogger<CurrentUserService> _logger;
    private CurrentUserInfo? _cached;
    private bool _resolved;

    public CurrentUserService(
        IHttpContextAccessor httpContextAccessor,
        IdentityDbContext db,
        ILogger<CurrentUserService> logger)
    {
        _httpContextAccessor = httpContextAccessor;
        _db = db;
        _logger = logger;
    }

    public async Task<CurrentUserInfo?> GetAsync()
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

        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (user is not null)
        {
            // Keep auth provider ID in sync
            if (user.ClerkId != firebaseUid && firebaseUid != "")
            {
                user.ClerkId = firebaseUid;
                user.UpdatedAt = DateTime.UtcNow;
                await _db.SaveChangesAsync();
            }

            _cached = new CurrentUserInfo(user.Id, user.Email);
            return _cached;
        }

        // New user
        user = new User
        {
            Id = Guid.NewGuid(),
            ClerkId = firebaseUid,
            Email = email!,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        _db.Users.Add(user);
        await _db.SaveChangesAsync();

        _cached = new CurrentUserInfo(user.Id, user.Email);
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
