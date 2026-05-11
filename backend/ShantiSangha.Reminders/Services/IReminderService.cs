using ShantiSangha.Reminders.Contracts;

namespace ShantiSangha.Reminders.Services;

public interface IReminderService
{
    Task<ReminderResponse> CreateAsync(Guid userId, CreateReminderRequest request, CancellationToken ct = default);
    Task<List<ReminderResponse>> ListAsync(Guid userId, Guid? connectionId = null, string? date = null, CancellationToken ct = default);
    Task<ReminderResponse?> GetByIdAsync(Guid id, Guid userId, string? date = null, CancellationToken ct = default);
    Task<bool> UpdateAsync(Guid id, Guid userId, UpdateReminderRequest request, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, Guid userId, CancellationToken ct = default);
}
