using ShantiSangha.Shared.Jyotish;

namespace ShantiSangha.Shared.Interfaces;

public interface IJyotishContextService
{
    Task<JyotishContext?> GetContextAsync(Guid userId, DateOnly date, CancellationToken ct = default);
}
