using ShantiSangha.Identity.Contracts;

namespace ShantiSangha.Identity.Services;

public interface IUserService
{
    Task<UserResponse?> GetMeAsync(Guid userId, CancellationToken ct = default);
    Task<bool> UpdateMeAsync(Guid userId, UpdateMeRequest request, CancellationToken ct = default);
}
