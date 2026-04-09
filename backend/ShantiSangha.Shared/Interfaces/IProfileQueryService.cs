namespace ShantiSangha.Shared.Interfaces;

public interface IProfileQueryService
{
    Task<string?> GetDisplayNameAsync(Guid userId, CancellationToken ct = default);
}
